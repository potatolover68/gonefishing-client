"""Local LUAR encoder for the Toolforge page.

Listens on http://127.0.0.1:11501. The page is on another origin, so every
response echoes that origin and allows the private-network preflight Chrome
sends from an HTTPS site.
"""

import json
import secrets
import sys
import threading
from pathlib import Path
from urllib.parse import parse_qs

from encode import LuarEncoder

ROOT = Path(__file__).resolve().parent
HOST = "127.0.0.1"
PORT = 11501
VECTOR_DIM = 512
MAX_BODY = 32 * 1024 * 1024

_jobs_lock = threading.Lock()
_jobs: dict[str, dict] = {}
_infer_lock = threading.Lock()
_encoder: LuarEncoder | None = None
_encoder_lock = threading.Lock()


class _Tee:
    def __init__(self, *streams) -> None:
        self._streams = streams

    def write(self, data: str) -> int:
        for stream in self._streams:
            if stream is None:
                continue
            stream.write(data)
            stream.flush()
        return len(data)

    def flush(self) -> None:
        for stream in self._streams:
            if stream is not None:
                stream.flush()


def _console(stream):
    if stream is None:
        return None
    try:
        if stream.isatty():
            return stream
    except Exception:
        return None
    return None


def _configure_stdio() -> None:
    log_dir = ROOT / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    handle = open(log_dir / "server.log", "a", encoding="utf-8", buffering=1)
    sys.stdout = _Tee(_console(sys.stdout), handle)
    sys.stderr = _Tee(_console(sys.stderr), handle)


def _encoder_instance() -> LuarEncoder:
    global _encoder
    with _encoder_lock:
        if _encoder is None:
            print("loading LUAR model", flush=True)
            _encoder = LuarEncoder(ROOT / "luar_mud.onnx", ROOT / "tokenizer.json")
            print("LUAR model ready", flush=True)
        return _encoder


def _origin(environ: dict) -> str:
    return environ.get("HTTP_ORIGIN") or "*"


def _cors(environ: dict, extra: list[tuple[str, str]] | None = None) -> list[tuple[str, str]]:
    headers = [
        ("Access-Control-Allow-Origin", _origin(environ)),
        ("Access-Control-Allow-Private-Network", "true"),
        ("Vary", "Origin"),
    ]
    if extra:
        headers.extend(extra)
    return headers


def _send(environ, start_response, status: str, body: bytes, content_type: str | None):
    extra = [("Content-Length", str(len(body)))]
    if content_type:
        extra.insert(0, ("Content-Type", content_type))
    start_response(status, _cors(environ, extra))
    if not body:
        return []
    return [body]


def _json(environ, start_response, status: str, payload: object):
    body = json.dumps(payload).encode("utf-8")
    return _send(environ, start_response, status, body, "application/json; charset=utf-8")


def _empty(environ, start_response, status: str, extra: list[tuple[str, str]] | None = None):
    start_response(status, _cors(environ, [("Content-Length", "0"), *(extra or [])]))
    return []


def _read_body(environ: dict) -> bytes:
    try:
        length = int(environ.get("CONTENT_LENGTH") or "0")
    except ValueError:
        length = 0
    if length < 0:
        length = 0
    if length > MAX_BODY:
        raise ValueError("request body is too large")
    return environ["wsgi.input"].read(length)


def _passages(raw: bytes) -> list[str]:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("expected a JSON array of strings") from exc
    if not isinstance(payload, list):
        raise ValueError("expected a JSON array of strings")
    if not payload:
        raise ValueError("expected at least one text")
    if any(not isinstance(item, str) for item in payload):
        raise ValueError("expected a JSON array of strings")
    return payload


def _run_job(qid: str, texts: list[str]) -> None:
    try:
        with _infer_lock:
            vector = _encoder_instance().embed_episode(texts)
        values = [float(item) for item in vector.reshape(-1).tolist()]
        if len(values) != VECTOR_DIM:
            raise RuntimeError(f"expected {VECTOR_DIM} values, got {len(values)}")
        record = {"status": "done", "vector": values}
    except Exception as exc:
        record = {"status": "error", "error": str(exc) or exc.__class__.__name__}
    with _jobs_lock:
        _jobs[qid] = record


def _start_job(texts: list[str]) -> str:
    qid = secrets.token_urlsafe(16)
    with _jobs_lock:
        _jobs[qid] = {"status": "running"}
    threading.Thread(target=_run_job, args=(qid, texts), name=f"embed-{qid}", daemon=True).start()
    return qid


def _query_qid(environ: dict) -> str:
    found = parse_qs(environ.get("QUERY_STRING") or "").get("qid", [])
    return found[0] if found else ""


def _handle(environ, start_response):
    method = environ.get("REQUEST_METHOD", "GET").upper()
    path = environ.get("PATH_INFO") or "/"

    if method == "OPTIONS":
        return _empty(
            environ,
            start_response,
            "204 No Content",
            [
                ("Access-Control-Allow-Methods", "GET, POST"),
                ("Access-Control-Allow-Headers", "Content-Type"),
            ],
        )

    if method == "GET" and path == "/status":
        return _empty(environ, start_response, "204 No Content")

    if method == "POST" and path == "/process":
        try:
            texts = _passages(_read_body(environ))
        except ValueError as exc:
            return _json(environ, start_response, "400 Bad Request", {"error": str(exc)})
        return _json(environ, start_response, "200 OK", {"qid": _start_job(texts)})

    if method == "GET" and path == "/done":
        qid = _query_qid(environ)
        with _jobs_lock:
            job = dict(_jobs[qid]) if qid in _jobs else None
        if job is None:
            return _json(
                environ,
                start_response,
                "404 Not Found",
                {"error": "unknown job"},
            )
        if job["status"] == "running":
            return _empty(environ, start_response, "202 Accepted")
        if job["status"] == "error":
            return _json(
                environ,
                start_response,
                "500 Internal Server Error",
                {"error": job.get("error") or "embedding failed"},
            )
        return _json(environ, start_response, "200 OK", job["vector"])

    return _json(environ, start_response, "404 Not Found", {"error": "not found"})


def app(environ, start_response):
    try:
        return _handle(environ, start_response)
    except Exception as exc:
        return _json(
            environ,
            start_response,
            "500 Internal Server Error",
            {"error": str(exc) or exc.__class__.__name__},
        )


def main() -> None:
    _configure_stdio()
    from waitress import serve

    print(f"listening on http://{HOST}:{PORT}", flush=True)
    serve(app, host=HOST, port=PORT, threads=8)


if __name__ == "__main__":
    main()
