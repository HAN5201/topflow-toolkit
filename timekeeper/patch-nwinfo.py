#!/usr/bin/env python3
"""Create a UTC-only B20 NITZ writer from a device-owned binary, never ship it.

At 0x31a68 replace the addition of signed quarter-hour timezone to the
QMI UTC calendar epoch with a plain move. Calendar validation, clock_settime,
NITZ timezone metadata and success notification remain intact. File offsets equal virtual
addresses in this B20 PT_LOAD segment. Unknown firmware is rejected.
"""
import hashlib
from pathlib import Path
import sys

ORIGINAL_SHA256 = '45d989f44b9a776bdbe84a2d59d8285e81ada0c18e9ae0c942c50ce99f51e4e6'
PATCHED_SHA256 = '01b66a930931f2eb63ab693d52e10642a3a4c5d36456a4d438a010571ba7c4d3'
OFFSET = 0x31a68
ORIGINAL = bytes.fromhex('20c0208b')  # add x0, x1, w0, sxtw
PATCHED = bytes.fromhex('e00301aa')   # mov x0, x1


def patch(data):
    digest = hashlib.sha256(data).hexdigest()
    if digest == PATCHED_SHA256:
        return data
    if digest != ORIGINAL_SHA256 or data[OFFSET:OFFSET + 4] != ORIGINAL:
        raise ValueError('unsupported nwinfo: firmware hash does not match audited B20')
    result = data[:OFFSET] + PATCHED + data[OFFSET + 4:]
    if hashlib.sha256(result).hexdigest() != PATCHED_SHA256:
        raise ValueError('patched nwinfo hash mismatch')
    return result


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: patch-nwinfo.py DEVICE_BINARY OUTPUT')
    try:
        result = patch(Path(sys.argv[1]).read_bytes())
    except ValueError as exc:
        sys.exit(str(exc))
    Path(sys.argv[2]).write_bytes(result)
    Path(sys.argv[2]).chmod(0o700)
