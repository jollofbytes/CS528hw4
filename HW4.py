"""HW4 Service 1: a plain Python web server that serves files from a Cloud Storage bucket.

Same logic as the HW3 Cloud Function, but we run the server ourselves:
  GET  /folder/1.html            -> file comes from the URL path
  POST {"filename": "folder/1.html"} -> file comes from the request body
  other methods                  -> 501
  missing file                   -> 404
  forbidden country (X-country)  -> 400, logged CRITICAL, sent to Service 2
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

from google.api_core.exceptions import NotFound
from google.cloud import logging as cloud_logging
from google.cloud import pubsub_v1, storage

BUCKET_NAME = os.environ.get("BUCKET_NAME", "cs528hww2")
PROJECT_ID = os.environ.get("PROJECT_ID", "solar-attic-508721-n0")
TOPIC_ID = os.environ.get("TOPIC_ID", "forbidden-requests")
PORT = int(os.environ.get("PORT", "80"))

FORBIDDEN_COUNTRIES = {
    "north korea", "iran", "cuba", "myanmar", "iraq",
    "libya", "sudan", "zimbabwe", "syria",
}

# Created once at startup and shared by every request
bucket = storage.Client(project=PROJECT_ID).bucket(BUCKET_NAME)
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
logger = cloud_logging.Client(project=PROJECT_ID).logger("hw4-file-server")


def log(severity, message, **fields):
    """Structured log entry in Cloud Logging (plus a copy on the console)."""
    print(f"[{severity}] {message}", flush=True)
    logger.log_struct({"message": message, **fields}, severity=severity)


class FileServer(BaseHTTPRequestHandler):

    # ---------- helpers ----------
    def respond(self, status, body, content_type="text/plain"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":  # HEAD responses must not have a body
            self.wfile.write(body)

    def filename_from_body(self):
        """POST: accept JSON {"filename": ...}, a form field filename=..., or the raw body."""
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8", errors="replace").strip()
        try:
            return str(json.loads(raw).get("filename", ""))
        except (ValueError, AttributeError):
            pass
        form = parse_qs(raw)
        if "filename" in form:
            return form["filename"][0]
        return raw

    def serve_file(self, filename):
        filename = filename.lstrip("/")
        country = self.headers.get("X-country", "").strip()

        # 400: forbidden country -> CRITICAL log + tell Service 2
        if country.lower() in FORBIDDEN_COUNTRIES:
            msg = {"country": country, "filename": filename, "method": self.command}
            log("CRITICAL", f"Forbidden request from {country} for {filename}", status=400, **msg)
            publisher.publish(topic_path, json.dumps(msg).encode("utf-8")).result()
            self.respond(400, f"400 Permission denied: requests from {country} are not allowed")
            return

        # 200 or 404
        try:
            content = bucket.blob(filename).download_as_bytes()
        except (NotFound, ValueError):  # ValueError = empty filename
            log("WARNING", f"404 Not Found: {filename}",
                status=404, method=self.command, filename=filename)
            self.respond(404, "404 Not Found")
            return
        self.respond(200, content, "text/html")

    def not_implemented(self):
        log("ERROR", f"501 Not Implemented: {self.command} {self.path}",
            status=501, method=self.command, path=self.path)
        self.respond(501, "501 Not Implemented")

    # ---------- HTTP methods ----------
    def do_GET(self):
        self.serve_file(unquote(urlparse(self.path).path))

    def do_POST(self):
        self.serve_file(self.filename_from_body())

    do_PUT = do_DELETE = do_HEAD = do_CONNECT = do_OPTIONS = do_TRACE = do_PATCH = not_implemented


if __name__ == "__main__":
    print(f"Serving gs://{BUCKET_NAME} on port {PORT}", flush=True)
    # Threading = one thread per request, so several clients can be served at once
    ThreadingHTTPServer(("0.0.0.0", PORT), FileServer).serve_forever()
