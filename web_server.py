#!/usr/bin/env python3
"""
Flutter Web 服务器 + WebDAV CORS 代理
- 静态文件服务 (build/web)
- /webdav-proxy/* 转发到坚果云 WebDAV (解决浏览器 CORS 限制)
"""
import http.server
import urllib.request
import urllib.error
import os
import sys

PORT = 9090
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')
WEBDAV_TARGET = 'https://dav.jianguoyun.com/dav'


class CORSProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PROPFIND, MKCOL, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Depth, Destination, Overwrite')
        super().end_headers()

    def do_OPTIONS(self):
        if self.path.startswith('/webdav-proxy/'):
            self.send_response(200)
            self.end_headers()
        else:
            super().do_OPTIONS() if hasattr(super(), 'do_OPTIONS') else self._send_405()

    def _send_405(self):
        self.send_response(405)
        self.end_headers()

    def _proxy_webdav(self, method):
        remote_path = self.path[len('/webdav-proxy'):]  # strip /webdav-proxy
        target_url = WEBDAV_TARGET + remote_path
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        req = urllib.request.Request(target_url, data=body, method=method)
        
        # Forward auth header
        auth = self.headers.get('Authorization')
        if auth:
            req.add_header('Authorization', auth)
        
        ct = self.headers.get('Content-Type')
        if ct:
            req.add_header('Content-Type', ct)
        
        depth = self.headers.get('Depth')
        if depth:
            req.add_header('Depth', depth)

        try:
            with urllib.request.urlopen(req) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for key in ['Content-Type', 'Content-Length', 'ETag', 'Last-Modified']:
                    val = resp.headers.get(key)
                    if val:
                        self.send_header(key, val)
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())

    def do_GET(self):
        if self.path.startswith('/webdav-proxy/'):
            self._proxy_webdav('GET')
        else:
            super().do_GET()

    def do_PUT(self):
        if self.path.startswith('/webdav-proxy/'):
            self._proxy_webdav('PUT')
        else:
            self.send_response(405)
            self.end_headers()

    def do_DELETE(self):
        if self.path.startswith('/webdav-proxy/'):
            self._proxy_webdav('DELETE')
        else:
            self.send_response(405)
            self.end_headers()

    def do_PROPFIND(self):
        if self.path.startswith('/webdav-proxy/'):
            self._proxy_webdav('PROPFIND')
        else:
            self.send_response(405)
            self.end_headers()

    def do_MKCOL(self):
        if self.path.startswith('/webdav-proxy/'):
            self._proxy_webdav('MKCOL')
        else:
            self.send_response(405)
            self.end_headers()

    def do_POST(self):
        if self.path.startswith('/webdav-proxy/'):
            self._proxy_webdav('POST')
        else:
            self.send_response(405)
            self.end_headers()


if __name__ == '__main__':
    os.chdir(WEB_DIR)
    print(f'Serving Flutter Web from {WEB_DIR} on http://localhost:{PORT}')
    print(f'WebDAV proxy: /webdav-proxy/* -> {WEBDAV_TARGET}/*')
    server = http.server.HTTPServer(('', PORT), CORSProxyHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nServer stopped.')
        server.server_close()
