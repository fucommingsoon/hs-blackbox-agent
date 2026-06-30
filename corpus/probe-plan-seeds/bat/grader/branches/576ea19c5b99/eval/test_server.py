"""
Simple HTTP server for testing bat executable.
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading
import time
import sys
from urllib.parse import parse_qs, urlparse

class TestRequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress logging to avoid cluttering test output
        pass
    
    def do_GET(self):
        parsed = urlparse(self.path)
        
        if parsed.path == '/json':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {"message": "hello", "method": "GET"}
            self.wfile.write(json.dumps(response).encode())
        
        elif parsed.path == '/echo-headers':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            headers = dict(self.headers)
            self.wfile.write(json.dumps(headers).encode())
        
        elif parsed.path == '/query':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            params = parse_qs(parsed.query)
            self.wfile.write(json.dumps(params).encode())
        
        elif parsed.path == '/status/404':
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not Found')
        
        elif parsed.path == '/download':
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="testfile.txt"')
            self.end_headers()
            self.wfile.write(b'Downloaded content')
        
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Hello World')
    
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        if self.path == '/echo':
            self.send_response(200)
            self.send_header('Content-Type', self.headers.get('Content-Type', 'text/plain'))
            self.end_headers()
            self.wfile.write(body)
        
        elif self.path == '/json':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            try:
                data = json.loads(body)
                response = {"received": data, "method": "POST"}
                self.wfile.write(json.dumps(response).encode())
            except:
                self.wfile.write(body)
        
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'POST received')
    
    def do_PUT(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response = {"method": "PUT", "body": body.decode('utf-8', errors='ignore')}
        self.wfile.write(json.dumps(response).encode())
    
    def do_DELETE(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response = {"method": "DELETE", "status": "deleted"}
        self.wfile.write(json.dumps(response).encode())
    
    def do_PATCH(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response = {"method": "PATCH"}
        self.wfile.write(json.dumps(response).encode())
    
    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('X-Custom-Header', 'test-value')
        self.end_headers()
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Allow', 'GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS')
        self.end_headers()

def start_server(port=8765):
    server = HTTPServer(('localhost', port), TestRequestHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    time.sleep(0.1)  # Give server time to start
    return server

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = start_server(port)
    print(f"Test server running on http://localhost:{port}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.shutdown()
