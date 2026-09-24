#!/usr/bin/env python3
"""Create a UTC-only B20 NTP client from a device-owned binary, never ship it.

At 0x4d44 branch to 0x4e88 after NTP epoch/fraction conversion, bypassing
vendor timezone/DST arithmetic. Packet validation, clock_settime, result
notification and retry logic remain intact. File offsets equal virtual
addresses in this B20 PT_LOAD segment. Unknown firmware is rejected.
"""
import hashlib
from pathlib import Path
import sys

ORIGINAL_SHA256 = 'f0dada95771df3aec5c2d3573f1168dfe2986e934619b3696d0ea187724bbcff'
PATCHED_SHA256 = '459d5d2e186aaeff1834625a14b976a18b5f8a581ce8711822aaeb4c9c80c9e1'
OFFSET = 0x4d44
ORIGINAL = bytes.fromhex('000340bd')  # ldr s0, [x24]
PATCHED = bytes.fromhex('51000014')   # b 0x4e88


def patch(data):
    digest = hashlib.sha256(data).hexdigest()
    if digest == PATCHED_SHA256:
        return data
    if digest != ORIGINAL_SHA256 or data[OFFSET:OFFSET + 4] != ORIGINAL:
        raise ValueError('unsupported ntpclient: firmware hash does not match audited B20')
    result = data[:OFFSET] + PATCHED + data[OFFSET + 4:]
    if hashlib.sha256(result).hexdigest() != PATCHED_SHA256:
        raise ValueError('patched ntpclient hash mismatch')
    return result


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: patch-ntpclient.py DEVICE_BINARY OUTPUT')
    try:
        result = patch(Path(sys.argv[1]).read_bytes())
    except ValueError as exc:
        sys.exit(str(exc))
    Path(sys.argv[2]).write_bytes(result)
    Path(sys.argv[2]).chmod(0o700)
