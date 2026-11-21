#!/usr/bin/env python3
"""Proxy local OpenSSH through the QEMU test container's loopback forwarding."""
import os
import select
import socket

with socket.create_connection(('127.0.0.1', 2222), timeout=5) as stream:
    stream.settimeout(None)
    sources = [0, stream]
    while True:
        ready, _, _ = select.select(sources, [], [])
        if 0 in ready:
            data = os.read(0, 65536)
            if data:
                stream.sendall(data)
            else:
                stream.shutdown(socket.SHUT_WR)
                sources.remove(0)
        if stream in ready:
            data = stream.recv(65536)
            if not data:
                break
            view = memoryview(data)
            while view:
                view = view[os.write(1, view):]
