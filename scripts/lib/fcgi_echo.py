#!/usr/bin/env python3
"""Minimal FastCGI responder for smoke tests (stdlib only).

    python3 fcgi_echo.py <unix-socket-path>

Answers every request with a text/plain body listing a few CGI params, so a
web server test can prove that its FastCGI proxy (e.g. Apache mod_proxy_fcgi
or nginx fastcgi_pass) really talks to a FastCGI backend over a unix socket.
"""
import os
import socket
import struct
import sys

BEGIN_REQUEST, END_REQUEST, PARAMS, STDIN, STDOUT = 1, 3, 4, 5, 6


def read_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def read_record(conn):
    version, rtype, req_id, clen, plen, _ = struct.unpack(">BBHHBB", read_exact(conn, 8))
    content = read_exact(conn, clen) if clen else b""
    if plen:
        read_exact(conn, plen)
    return rtype, req_id, content


def parse_params(data):
    params, i = {}, 0

    def length():
        nonlocal i
        if data[i] >> 7:
            n = struct.unpack(">I", data[i:i + 4])[0] & 0x7FFFFFFF
            i += 4
        else:
            n = data[i]
            i += 1
        return n

    while i < len(data):
        nl = length()
        vl = length()
        name = data[i:i + nl].decode("latin-1")
        i += nl
        params[name] = data[i:i + vl].decode("latin-1")
        i += vl
    return params


def record(rtype, req_id, content=b""):
    return struct.pack(">BBHHBB", 1, rtype, req_id, len(content), 0, 0) + content


def handle(conn):
    params_raw, req_id = b"", 1
    while True:
        rtype, req_id, content = read_record(conn)
        if rtype == PARAMS:
            params_raw += content
        elif rtype == STDIN and not content:
            break
    p = parse_params(params_raw)
    body = "fcgi-ok\nSCRIPT_FILENAME={}\nHTTPS={}\nREQUEST_URI={}\n".format(
        p.get("SCRIPT_FILENAME", ""), p.get("HTTPS", ""), p.get("REQUEST_URI", ""))
    out = ("Content-Type: text/plain\r\nX-Fcgi-Echo: 1\r\n\r\n" + body).encode()
    conn.sendall(record(STDOUT, req_id, out) + record(STDOUT, req_id)
                 + record(END_REQUEST, req_id, struct.pack(">IB3x", 0, 0)))


def main():
    path = sys.argv[1]
    if os.path.exists(path):
        os.unlink(path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(8)
    while True:
        conn, _ = srv.accept()
        try:
            handle(conn)
        except (EOFError, OSError):
            pass
        finally:
            conn.close()


if __name__ == "__main__":
    main()
