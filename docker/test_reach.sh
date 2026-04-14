#!/bin/sh
ip route add 192.168.100.0/24 via 192.168.65.254 2>&1 || true
python3 -c "
import socket
hosts = {'vmm01': '192.168.100.60', 'dc01': '192.168.100.10', 'db01': '192.168.100.30'}
for name, ip in hosts.items():
    try:
        s = socket.create_connection((ip, 22), timeout=3)
        banner = s.recv(64).decode(errors='ignore').strip()
        s.close()
        print(f'{name} ({ip}) SSH OK: {banner}')
    except Exception as e:
        print(f'{name} ({ip}) SSH FAIL: {e}')
"
