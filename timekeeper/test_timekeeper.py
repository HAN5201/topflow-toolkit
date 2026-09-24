#!/usr/bin/env python3
"""Exercise real shell functions with isolated files and mocked device services."""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

SOURCE = Path(__file__).with_name('timekeeper.sh').read_text().split('\ncase "${1:-status}" in')[0]


class TimekeeperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for directory in ('data/timekeeper', 'etc', 'tmp', 'bin'):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        (self.root / 'etc/TZ').symlink_to(self.root / 'tmp/TZ')
        (self.root / 'etc/localtime').symlink_to(self.root / 'tmp/localtime')
        (self.root / 'tmp/TZ').write_text('UTC\n')
        self.db = self.root / 'uci.json'
        self.values = {
            'system.@system[0].timezone': 'UTC',
            'zwrt_zte_sntp.settings.timezone': '8',
            'zwrt_zte_sntp.settings.dst_enable': '0',
            'zwrt_zte_sntp.settings.auto_tz_dst_switch': '0',
        }
        self.save()
        mock = self.root / 'bin/uci'
        mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['UCI_DB']); d=json.loads(p.read_text())
a=[x for x in sys.argv[1:] if x != '-q']; op=a[0]
if op == 'get':
    if a[1] not in d: sys.exit(1)
    print(d[a[1]])
elif op == 'changes':
    if d.get('_pending'): print('pending unrelated change')
elif op == 'set':
    k,v=a[1].split('=',1); d[k]=v; p.write_text(json.dumps(d))
elif op == 'delete':
    d.pop(a[1],None); p.write_text(json.dumps(d))
elif op == 'commit':
    d['_commits']=d.get('_commits',0)+1; p.write_text(json.dumps(d))
else: sys.exit(2)
''')
        mock.chmod(0o755)
        # Substitute once: Linux temp roots themselves start with /tmp/.
        self.source = re.sub(r"/data/timekeeper|/tmp/|/etc/",
                             lambda match: str(self.root) + match.group(), SOURCE)

    def tearDown(self):
        self.tmp.cleanup()

    def save(self):
        self.db.write_text(json.dumps(self.values))

    def run_shell(self, body, check=True):
        env = dict(os.environ, PATH=str(self.root / 'bin') + ':' + os.environ['PATH'], UCI_DB=str(self.db))
        return subprocess.run(['sh', '-c', self.source + '\n' + body], env=env,
                              check=check, text=True, capture_output=True)

    def test_fixed_offset_signs_and_fractional_zones(self):
        for value, expected in [('8','CST-8'), ('5.5','UTC-5:30'), ('-3.5','UTC+3:30'),
                                ('5.75','UTC-5:45'), ('0','UTC-0:00'), ('14','UTC-14:00')]:
            with self.subTest(value=value):
                self.values['zwrt_zte_sntp.settings.timezone'] = value
                self.save()
                self.assertEqual(self.run_shell('configured_timezone').stdout.strip(), expected)
        for value in ('15', '-13', '8junk', '', '0.001'):
            self.values['zwrt_zte_sntp.settings.timezone'] = value
            self.save()
            self.assertNotEqual(self.run_shell('configured_timezone', check=False).returncode, 0)

    def test_apply_idempotence_and_restore(self):
        self.run_shell('apply_timezone; apply_timezone')
        self.assertEqual((self.root / 'tmp/TZ').read_text(), 'CST-8\n')
        current = json.loads(self.db.read_text())
        self.assertEqual(current['_commits'], 1)
        self.assertEqual(current['system.@system[0].timezone'], 'CST-8')
        self.run_shell('restore_timezone')
        self.assertEqual((self.root / 'tmp/TZ').read_text(), 'UTC\n')
        self.assertEqual(json.loads(self.db.read_text())['system.@system[0].timezone'], 'UTC')

    def test_tzif_is_readable_with_correct_offsets_through_2099(self):
        for value in ('8', '5.5', '-3.5', '5.75', '0', '-12', '14'):
            self.values['zwrt_zte_sntp.settings.timezone'] = value
            self.save()
            self.run_shell('apply_timezone')
            with (self.root / 'data/timekeeper/localtime').open('rb') as f:
                zone = ZoneInfo.from_file(f)
            for year in (2026, 2040, 2099):
                instant = datetime(year, 9, 13, tzinfo=timezone.utc).astimezone(zone)
                self.assertEqual(instant.utcoffset().total_seconds(), float(value) * 3600)

    def test_preserve_later_user_timezone(self):
        self.run_shell('apply_timezone')
        self.values = json.loads(self.db.read_text())
        self.values['system.@system[0].timezone'] = 'UTC-9'
        self.save()
        self.run_shell('restore_timezone')
        self.assertEqual(json.loads(self.db.read_text())['system.@system[0].timezone'], 'UTC-9')
        self.assertEqual((self.root / 'etc/localtime').readlink(), self.root / 'tmp/localtime')

    def test_enabling_vendor_dst_releases_owned_timezone_file(self):
        self.run_shell('apply_timezone')
        self.values = json.loads(self.db.read_text())
        self.values['zwrt_zte_sntp.settings.dst_enable'] = '1'
        self.save()
        self.run_shell('apply_timezone; apply_timezone')
        self.assertEqual((self.root / 'etc/localtime').readlink(), self.root / 'tmp/localtime')
        self.assertEqual(json.loads(self.db.read_text())['system.@system[0].timezone'], 'UTC')

    def test_pending_changes_and_vendor_dst_are_not_overwritten(self):
        self.values['_pending'] = True
        self.save()
        self.assertNotEqual(self.run_shell('apply_timezone', check=False).returncode, 0)
        self.assertEqual((self.root / 'tmp/TZ').read_text(), 'UTC\n')
        self.values.pop('_pending')
        for option in ('dst_enable', 'auto_tz_dst_switch'):
            self.values['zwrt_zte_sntp.settings.' + option] = '1'
            self.save()
            self.run_shell('apply_timezone')
            self.assertNotIn('_commits', json.loads(self.db.read_text()))
            self.values['zwrt_zte_sntp.settings.' + option] = '0'

    def test_late_network_and_resync_are_saved_once_each(self):
        self.run_shell('''
elapsed=0
cut() { echo "$elapsed"; }
sleep() { elapsed=$((elapsed + $1)); [ "$elapsed" -lt 1900 ] || exit 0; }
prepare_clock() { :; }
sntp_synced() { [ "$elapsed" -ge 905 ] && { [ "$elapsed" -lt 1300 ] || [ "$elapsed" -ge 1400 ]; }; }
sync_now() { echo "$elapsed" >>"$BASE/saves"; echo "$elapsed" >"$SYNC_MARKER"; }
watch_for_sync
''')
        saves = [int(x) for x in (self.root / 'data/timekeeper/saves').read_text().splitlines()]
        self.assertEqual(len(saves), 2)
        self.assertGreaterEqual(saves[0], 905)
        self.assertGreaterEqual(saves[1], 1400)

    def test_restart_does_not_repeat_successful_save(self):
        self.run_shell('''
echo 1789280000 >"$SYNC_MARKER"
elapsed=0
cut() { echo "$elapsed"; }
sleep() { elapsed=$((elapsed + $1)); [ "$elapsed" -lt 1000 ] || exit 0; }
prepare_clock() { :; }
sntp_synced() { return 0; }
sync_now() { echo unexpected >"$BASE/saves"; }
watch_for_sync
''')
        self.assertFalse((self.root / 'data/timekeeper/saves').exists())

    def test_offline_never_writes_offset(self):
        result = self.run_shell('utc_clock_ready() { return 0; }; sntp_synced() { return 1; }; sync_now', check=False)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / 'tmp/timekeeper-synced').exists())

    def test_old_sntp_success_cannot_bypass_utc_guard(self):
        result = self.run_shell('utc_clock_ready() { return 1; }; sntp_synced() { return 0; }; sync_now', check=False)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / 'tmp/timekeeper-synced').exists())
        self.assertIn('UTC NTP compatibility is not active', (self.root / 'tmp/timekeeper.log').read_text())

    def test_unsupported_firmware_is_not_patched(self):
        import importlib.util
        import sys
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location('ntp_patch', Path(__file__).with_name('patch-ntpclient.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            module.patch(bytes(0x5000))

    def test_unpatched_process_blocks_persistence(self):
        self.run_shell('apply_timezone')
        body = """
: >"$UTC_READY"
file_sha() { if [ "$1" = "$NTP_CLIENT" ]; then echo "$NTP_UTC_SHA"; else echo "$NTP_ORIGINAL_SHA"; fi; }
pidof() { echo 123; }
utc_clock_ready
"""
        self.assertNotEqual(self.run_shell(body, check=False).returncode, 0)
        self.assertEqual(self.run_shell(body.replace('echo "$NTP_ORIGINAL_SHA"', 'echo "$NTP_UTC_SHA"'), check=False).returncode, 0)

    def test_dst_never_passes_utc_guard(self):
        self.values['zwrt_zte_sntp.settings.dst_enable'] = '1'
        self.save()
        result = self.run_shell(': >"$UTC_READY"; file_sha() { echo "$NTP_UTC_SHA"; }; utc_clock_ready', check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_existing_sntp_client_restarts_detached_without_waiting_for_wan_event(self):
        body = """
pidof() { [ "$1" = zte_topsw_ntp ]; }
killall() { :; }
ubus() { echo "$*" >>"$BASE/ubus-calls"; }
jsonfilter() { cat >/dev/null; echo SNTP; }
nohup() { echo "$*" >"$BASE/launch"; }
restart_ntp_if_running
"""
        self.run_shell(body)
        self.assertEqual((self.root / 'data/timekeeper/launch').read_text().strip(), 'sh /sbin/zte_ntp_cy.sh start')
        self.assertIn('ntpclient_sync_rslt {"sync":false}', (self.root / 'data/timekeeper/ubus-calls').read_text())

    def test_manual_mode_does_not_launch_ntp(self):
        self.run_shell("""
pidof() { [ "$1" = zte_topsw_ntp ]; }
ubus() { :; }
jsonfilter() { cat >/dev/null; echo MANUAL; }
nohup() { echo unexpected >"$BASE/launch"; }
restart_ntp_if_running
""")
        self.assertFalse((self.root / 'data/timekeeper/launch').exists())

    def test_vendor_start_prerequisite_is_idempotent_and_reversible(self):
        fixture = self.root / 'ntp.init'
        original = '#!/bin/sh /etc/rc.common\nstart_service() {\n    procd_open_instance\n}\n'
        fixture.write_text(original)
        env = dict(os.environ, NTP_INIT=str(fixture))
        hook = Path(__file__).with_name('ntp-boot-hook.sh')
        for _ in range(2):
            subprocess.run(['sh', str(hook), 'install'], env=env, check=True)
        patched = fixture.read_text()
        self.assertEqual(patched.count('prepare-clock'), 1)
        self.assertLess(patched.index('prepare-clock'), patched.index('procd_open_instance'))
        subprocess.run(['sh', str(hook), 'remove'], env=env, check=True)
        self.assertEqual(fixture.read_text(), original)
        fixture.write_text('unrecognized vendor service\n')
        result = subprocess.run(['sh', str(hook), 'install'], env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(fixture.read_text(), 'unrecognized vendor service\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
