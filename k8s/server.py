from http.server import HTTPServer, BaseHTTPRequestHandler

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            try:
                with open("/tmp/hubitat_metrics", "r") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(content.encode())
            except:
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(("", 5000), MetricsHandler).serve_forever()
