#!/usr/bin/env python3
"""Control only the test VM's headless QMP or serial socket."""
import json
import pathlib
import secrets
import shlex
import socket
import sys
import time

media, case, action, *args = sys.argv[1:]
assert media in ('TF', 'eMMC')
assert case in ('minimum', 'stale-gpt', 'installer', 'grown-gpt')
vm = pathlib.Path('work') / f'v2-vm-{media}-{case}'
credentials = vm / 'credentials'
if action == 'serial':
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(55)
        sock.connect(str(vm / 'serial.sock'))
        def read_until(*tokens):
            data = b''
            while not any(token in data for token in tokens):
                chunk = sock.recv(16384)
                if not chunk:
                    raise RuntimeError(f'Serial EOF: {data!r}')
                data += chunk
            # Terminal echo may include the keyed commands; do not echo the password.
            print(data.decode(errors='replace'), flush=True)
            return data
        sock.sendall(b'\x03\r')
        prompt = read_until(b'login:', b'$ ')
        if b'$ ' not in prompt:
            sock.sendall(b'k4test\r')
            read_until(b'Password:', '密码：'.encode())
            sock.sendall(credentials.read_bytes().strip() + b'\r')
            read_until(b'$ ')
        command = args[0] if args else 'cat /etc/k4-boot-medium; findmnt -no SOURCE,UUID,TARGET /; findmnt -no SOURCE,UUID,TARGET /boot; systemctl is-active gdm NetworkManager ssh k4-grow-root; swapon --show; locale; id; loginctl --no-legend list-sessions'
        sock.sendall((command + '\r').encode())
        read_until(b'$ ')
        sock.sendall(b'exit\r')
    sys.exit(0)

with socket.socket(socket.AF_UNIX) as sock:
    sock.settimeout(30)
    sock.connect(str(vm / 'qmp.sock'))
    stream = sock.makefile('rwb')
    def line():
        return json.loads(stream.readline())
    assert 'QMP' in line()
    def qmp(command, **kwargs):
        stream.write((json.dumps({'execute': command, 'arguments': kwargs}) + '\r\n').encode())
        stream.flush()
        while True:
            reply = line()
            if 'event' in reply:
                continue
            if 'error' in reply:
                raise RuntimeError(reply)
            return reply['return']
    qmp('qmp_capabilities')
    def sendkey(key):
        result = qmp('human-monitor-command', **{'command-line': f'sendkey {key} 105'})
        if result and result.strip():
            raise RuntimeError(result)
        time.sleep(.18)
    def text(value):
        for c in value:
            key = 'ret' if c == '\n' else 'shift-' + c.lower() if c.isupper() else c
            sendkey(key)
    if action == 'screenshot':
        name = args[0] if args else 'screen'
        assert name.isalnum() or '-' in name and all(x.isalnum() for x in name.split('-'))
        qmp('screendump', filename=f'/task/{vm}/{name}.ppm')
    elif action == 'keys':
        for key in args:
            sendkey(key)
    elif action == 'click':
        x, y, width, height = map(int, args)
        assert 0 <= x < width and 0 <= y < height
        qmp('input-send-event', events=[
            {'type': 'abs', 'data': {'axis': 'x', 'value': round(32767*x/(width-1))}},
            {'type': 'abs', 'data': {'axis': 'y', 'value': round(32767*y/(height-1))}},
        ])
        time.sleep(.25)
        for pressed in (True, False):
            qmp('input-send-event', events=[{'type': 'btn', 'data': {'down': pressed, 'button': 'left'}}])
            time.sleep(.15)
    elif action == 'username':
        text('k4test\n')
    elif action == 'new-password':
        # Call only after observing the actual New password prompt.
        password = 'Test' + secrets.token_hex(12)
        credentials.write_text(password + '\n')
        credentials.chmod(0o600)
        text(password+'\n')
    elif action == 'confirm-password':
        # Call only after observing the actual Retype new password prompt.
        text(credentials.read_text())
    elif action == 'login':
        sendkey('ret')
        time.sleep(5)
        text(credentials.read_text())
    elif action == 'quit':
        qmp('quit')
    else:
        raise ValueError(action)
