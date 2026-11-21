#!/usr/bin/env python3
"""Launch with private binfmt and a 1:1 uid/gid map (inside the build container)."""
import ctypes
import os
import sys

ready_r, ready_w = os.pipe()
go_r, go_w = os.pipe()
pid = os.fork()
if pid == 0:
    os.close(ready_r)
    os.close(go_w)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.unshare(0x10000000) != 0:  # CLONE_NEWUSER
        e = ctypes.get_errno()
        raise OSError(e, os.strerror(e))
    os.write(ready_w, b'1')
    if os.read(go_r, 1) != b'1':
        sys.exit(1)
    os.execvp('unshare', ['unshare', '-m', '--propagation', 'private', *sys.argv[1:]])
os.close(ready_w)
os.close(go_r)
if os.read(ready_r, 1) != b'1':
    sys.exit(1)
for name in ('uid_map', 'gid_map'):
    with open(f'/proc/{pid}/{name}', 'w') as f:
        f.write('0 0 65536\n')
os.write(go_w, b'1')
_, status = os.waitpid(pid, 0)
code = os.waitstatus_to_exitcode(status)
sys.exit(code if code >= 0 else 128 - code)
