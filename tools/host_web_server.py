#!/usr/bin/env python3
"""
Single-Port Web + WebSocket Bridge Server for Khartoum Al-Azhari (Godot 4.7.2).

- Serves `builds/web/` static HTML5/WebGL2 files on `http://0.0.0.0:8080`
- Pre-caches and serves Gzip-compressed `.wasm`, `.pck`, `.js`, and `.html` assets
  (`Content-Encoding: gzip` + `Cache-Control: public, max-age=3600`) whenever the
  browser sends `Accept-Encoding: gzip`, cutting transfer size by 65-75%.
- Transparently proxies `/ws` WebSocket upgrade connections directly to Godot's
  local `WebSocketMultiplayerPeer` server on `127.0.0.1:7778`.
"""

import argparse
import asyncio
import gzip
import mimetypes
import shutil
import socket
from pathlib import Path
from urllib.parse import unquote

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = PROJECT_ROOT / "builds" / "web"

GZIPPABLE_EXTS = {".wasm", ".pck", ".js", ".mjs", ".html", ".json", ".css", ".svg"}
STREAM_CHUNK_BYTES = 65536
WS_PING_INTERVAL_SEC = 25.0
_GZIP_LOCKS: dict[str, asyncio.Lock] = {}

MIME_OVERRIDES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".json": "application/json; charset=utf-8",
    ".css": "text/css; charset=utf-8",
}

FALLBACK_HTML = """<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>الخرطوم - حي الأزهري | Khartoum Al-Azhari Web Server</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
           background: #12151c; color: #f4efe6; margin: 0; display: flex; align-items: center;
           justify-content: center; min-height: 100vh; padding: 20px; box-sizing: border-box; }
    .card { max-width: 520px; width: 100%; background: #1c222d; border: 1px solid #354154;
            border-radius: 14px; padding: 24px; box-shadow: 0 12px 32px rgba(0,0,0,0.45); }
    h1 { margin-top: 0; font-size: 1.4rem; color: #f5c26b; }
    p, li { line-height: 1.6; font-size: 0.95rem; color: #d7d2c8; }
    code { background: #10141b; padding: 2px 6px; border-radius: 5px; color: #7ce38b; direction: ltr; display: inline-block; }
    .status { margin-top: 16px; padding: 12px; border-radius: 8px; background: #152922; border: 1px solid #2b6e51; color: #98f5c4; }
  </style>
</head>
<body>
  <div class="card">
    <h1>الخرطوم - حي الأزهري (Web + WebSocket Bridge Active)</h1>
    <p>خادم الويب وجسر WebSocket يعملان بنجاح على المنفذ <code>8080</code> مع تحويل تلقائي لمسار <code>/ws</code> إلى خادم Godot على <code>127.0.0.1:7778</code>.</p>
    <div class="status" id="ws-status">جاهز لتوصيل لاعبي iPhone Safari عبر <code>/ws</code> &rarr; <code>127.0.0.1:7778</code></div>
  </div>
</body>
</html>
""".encode("utf-8")


def get_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


def ensure_gzip_cache(target_file: Path) -> Path:
    """Create or refresh a pre-compressed `.gz` sidecar file for fast zero-stall streaming."""
    gz_path = target_file.with_name(target_file.name + ".gz")
    src_stat = target_file.stat()
    if gz_path.is_file():
        gz_stat = gz_path.stat()
        if gz_stat.st_mtime >= src_stat.st_mtime and gz_stat.st_size > 0:
            return gz_path

    tmp_gz = target_file.with_name(target_file.name + ".gz.tmp")
    with target_file.open("rb") as f_in, gzip.open(tmp_gz, "wb", compresslevel=6) as f_out:
        shutil.copyfileobj(f_in, f_out, length=1024 * 1024)
    tmp_gz.replace(gz_path)
    return gz_path


def prewarm_web_dir_gzip(web_dir: Path) -> None:
    if not web_dir.is_dir():
        return
    for item in sorted(web_dir.iterdir()):
        if item.is_file() and item.suffix.lower() in GZIPPABLE_EXTS:
            try:
                gz = ensure_gzip_cache(item)
                raw_mb = item.stat().st_size / (1024 * 1024)
                gz_mb = gz.stat().st_size / (1024 * 1024)
                ratio = (1.0 - (gz_mb / raw_mb)) * 100.0 if raw_mb > 0 else 0.0
                print(f"[Gzip Cache] {item.name:28s}: {raw_mb:6.2f} MB -> {gz_mb:6.2f} MB ({ratio:.1f}% smaller)")
            except Exception as exc:
                print(f"[Gzip Cache] Warning on {item.name}: {exc}")


def _configure_socket(writer: asyncio.StreamWriter) -> None:
    sock = writer.get_extra_info("socket")
    if sock is None:
        return
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception:
        pass
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except Exception:
        pass


async def ensure_gzip_cache_async(target_file: Path) -> Path:
    key = str(target_file.resolve())
    lock = _GZIP_LOCKS.setdefault(key, asyncio.Lock())
    async with lock:
        return await asyncio.to_thread(ensure_gzip_cache, target_file)


async def _pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(STREAM_CHUNK_BYTES)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def _read_ws_frame(reader: asyncio.StreamReader) -> bytes:
    """Read exactly one RFC 6455 WebSocket frame so keepalive pings only inject between frames."""
    head = await reader.readexactly(2)
    b1, b2 = head[0], head[1]
    masked = (b2 & 0x80) != 0
    length = b2 & 0x7F
    ext = b""
    if length == 126:
        ext = await reader.readexactly(2)
        length = int.from_bytes(ext, "big")
    elif length == 127:
        ext = await reader.readexactly(8)
        length = int.from_bytes(ext, "big")
    mask_key = await reader.readexactly(4) if masked else b""
    payload = await reader.readexactly(length) if length > 0 else b""
    return head + ext + mask_key + payload


async def _pipe_ws_frames_locked(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    write_lock: asyncio.Lock,
) -> None:
    try:
        while True:
            frame = await _read_ws_frame(reader)
            async with write_lock:
                writer.write(frame)
                await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def _ws_ping_keepalive(
    writer: asyncio.StreamWriter,
    write_lock: asyncio.Lock,
    stop_event: asyncio.Event,
) -> None:
    try:
        while not stop_event.is_set():
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=WS_PING_INTERVAL_SEC)
                break
            except asyncio.TimeoutError:
                pass
            async with write_lock:
                # RFC 6455 unmasked server->client Ping frame (FIN=1, opcode=0x9, len=0)
                writer.write(b"\x89\x00")
                await writer.drain()
    except Exception:
        pass


async def _proxy_websocket(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    raw_request_line: str,
    headers_list: list[tuple[str, str]],
    headers_lower: dict[str, str],
    ws_host: str,
    ws_port: int,
) -> None:
    peer_addr = client_writer.get_extra_info("peername")
    print(f"[WS Proxy] Incoming /ws upgrade from {peer_addr} -> {ws_host}:{ws_port}", flush=True)
    _configure_socket(client_writer)
    try:
        backend_reader, backend_writer = await asyncio.wait_for(
            asyncio.open_connection(ws_host, ws_port), timeout=5.0
        )
    except Exception as exc:
        print(f"[WS Proxy] ERROR connecting to {ws_host}:{ws_port} for {peer_addr}: {exc}", flush=True)
        err_resp = (
            f"HTTP/1.1 503 Service Unavailable\r\n"
            f"Content-Type: text/plain; charset=utf-8\r\n"
            f"Connection: close\r\n\r\n"
            f"Godot WebSocket server ({ws_host}:{ws_port}) is unreachable: {exc}\n"
        ).encode("utf-8")
        try:
            client_writer.write(err_resp)
            await client_writer.drain()
            client_writer.close()
            await client_writer.wait_closed()
        except Exception:
            pass
        return

    _configure_socket(backend_writer)

    # Rebuild upgrade headers with canonical WebSocket header casing for Godot WSLPeer,
    # preserving Sec-WebSocket-Key, Sec-WebSocket-Version, and Sec-WebSocket-Protocol.
    canonical_lines = [raw_request_line]
    canonical_names = {
        "host": "Host",
        "upgrade": "Upgrade",
        "connection": "Connection",
        "sec-websocket-key": "Sec-WebSocket-Key",
        "sec-websocket-version": "Sec-WebSocket-Version",
        "sec-websocket-protocol": "Sec-WebSocket-Protocol",
        "origin": "Origin",
    }
    has_upgrade = False
    has_connection = False
    for k, v in headers_list:
        kl = k.lower()
        if kl == "sec-websocket-extensions":
            # Strip permessage-deflate so WebSocket frames stay uncompressed (prevents stream_peer_gzip.cpp errors)
            continue
        elif kl == "upgrade":
            canonical_lines.append("Upgrade: websocket")
            has_upgrade = True
        elif kl == "connection":
            canonical_lines.append("Connection: Upgrade")
            has_connection = True
        elif kl in canonical_names:
            canonical_lines.append(f"{canonical_names[kl]}: {v}")
        else:
            canonical_lines.append(f"{k}: {v}")
    if not has_upgrade:
        canonical_lines.append("Upgrade: websocket")
    if not has_connection:
        canonical_lines.append("Connection: Upgrade")
    forwarded_req = ("\r\n".join(canonical_lines) + "\r\n\r\n").encode("iso-8859-1")

    try:
        backend_writer.write(forwarded_req)
        await backend_writer.drain()
    except Exception as exc:
        print(f"[WS Proxy] ERROR writing upgrade request to backend for {peer_addr}: {exc}", flush=True)
        backend_writer.close()
        client_writer.close()
        return

    # Forward HTTP 101 Switching Protocols response first before framing begins
    try:
        handshake_resp = await asyncio.wait_for(backend_reader.readuntil(b"\r\n\r\n"), timeout=10.0)
        status_line = handshake_resp.split(b"\r\n", 1)[0].decode("iso-8859-1", errors="replace")
        print(f"[WS Proxy] Handshake {peer_addr} -> {status_line}", flush=True)
        client_writer.write(handshake_resp)
        await client_writer.drain()
    except Exception as exc:
        print(f"[WS Proxy] ERROR during 101 handshake for {peer_addr}: {exc}", flush=True)
        backend_writer.close()
        client_writer.close()
        return

    client_write_lock = asyncio.Lock()
    stop_event = asyncio.Event()
    ping_task = asyncio.create_task(_ws_ping_keepalive(client_writer, client_write_lock, stop_event))
    try:
        await asyncio.gather(
            _pipe_stream(client_reader, backend_writer),
            _pipe_ws_frames_locked(backend_reader, client_writer, client_write_lock),
            return_exceptions=True,
        )
    except Exception as exc:
        print(f"[WS Proxy] Stream error for {peer_addr}: {exc}", flush=True)
    finally:
        print(f"[WS Proxy] Disconnected {peer_addr}", flush=True)
        stop_event.set()
        ping_task.cancel()
        try:
            await ping_task
        except Exception:
            pass
        for w in (backend_writer, client_writer):
            try:
                w.close()
            except Exception:
                pass


def _guess_mime(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in MIME_OVERRIDES:
        return MIME_OVERRIDES[ext]
    guessed, _ = mimetypes.guess_type(str(path))
    return guessed or "application/octet-stream"


async def _handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    web_dir: Path,
    ws_host: str,
    ws_port: int,
) -> None:
    _configure_socket(writer)
    try:
        raw_head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=60.0)
    except Exception:
        writer.close()
        return

    header_text = raw_head.decode("iso-8859-1", errors="replace")
    lines = header_text.split("\r\n")
    if not lines or " " not in lines[0]:
        writer.close()
        return

    parts = lines[0].split(" ")
    method = parts[0].upper()
    raw_target = parts[1] if len(parts) > 1 else "/"
    path_only = unquote(raw_target.split("?", 1)[0])

    headers_lower: dict[str, str] = {}
    headers_list: list[tuple[str, str]] = []
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            k_clean = k.strip()
            v_clean = v.strip()
            headers_list.append((k_clean, v_clean))
            headers_lower[k_clean.lower()] = v_clean

    is_ws_upgrade = (
        headers_lower.get("upgrade", "").lower() == "websocket"
        or "upgrade" in headers_lower.get("connection", "").lower()
    )
    if is_ws_upgrade or path_only == "/ws" or path_only.startswith("/ws/"):
        await _proxy_websocket(reader, writer, lines[0], headers_list, headers_lower, ws_host, ws_port)
        return

    if method not in ("GET", "HEAD"):
        resp = b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        writer.write(resp)
        await writer.drain()
        writer.close()
        return

    rel_path = "index.html" if path_only in ("", "/") else path_only.lstrip("/")
    target_file = (web_dir / rel_path).resolve()

    if not str(target_file).startswith(str(web_dir.resolve())):
        writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        await writer.drain()
        writer.close()
        return

    if not target_file.is_file():
        if rel_path == "index.html":
            body = FALLBACK_HTML
            hdr = (
                f"HTTP/1.1 200 OK\r\n"
                f"Content-Type: text/html; charset=utf-8\r\n"
                f"Content-Length: {len(body)}\r\n"
                f"Cache-Control: no-cache\r\n"
                f"Connection: close\r\n\r\n"
            ).encode("iso-8859-1")
            writer.write(hdr if method == "HEAD" else hdr + body)
            await writer.drain()
            writer.close()
            return
        writer.write(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        await writer.drain()
        writer.close()
        return

    mime = _guess_mime(target_file)
    ext = target_file.suffix.lower()
    accept_enc = headers_lower.get("accept-encoding", "").lower()
    use_gzip = "gzip" in accept_enc and ext in GZIPPABLE_EXTS

    serve_file = target_file
    extra_headers = ""
    if use_gzip:
        try:
            serve_file = await ensure_gzip_cache_async(target_file)
            extra_headers = "Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n"
        except Exception:
            serve_file = target_file
            extra_headers = ""

    file_size = serve_file.stat().st_size
    etag = f'W/"{int(target_file.stat().st_mtime)}-{target_file.stat().st_size}"'
    no_cache_asset = target_file.name in ("index.html", "index.js")
    cache_hdr = "no-cache, must-revalidate" if no_cache_asset else "public, max-age=3600"

    if not no_cache_asset and headers_lower.get("if-none-match") == etag:
        hdr_304 = (
            f"HTTP/1.1 304 Not Modified\r\n"
            f"Cache-Control: {cache_hdr}\r\n"
            f"ETag: {etag}\r\n"
            f"Connection: close\r\n\r\n"
        ).encode("iso-8859-1")
        writer.write(hdr_304)
        await writer.drain()
        writer.close()
        return

    hdr = (
        f"HTTP/1.1 200 OK\r\n"
        f"Content-Type: {mime}\r\n"
        f"Content-Length: {file_size}\r\n"
        f"Cache-Control: {cache_hdr}\r\n"
        f"ETag: {etag}\r\n"
        f"{extra_headers}"
        f"Access-Control-Allow-Origin: *\r\n"
        f"Connection: close\r\n\r\n"
    ).encode("iso-8859-1")
    writer.write(hdr)
    await writer.drain()

    if method == "GET":
        try:
            with serve_file.open("rb") as f:
                sent_bytes = 0
                while sent_bytes < file_size:
                    to_read = min(STREAM_CHUNK_BYTES, file_size - sent_bytes)
                    chunk = f.read(to_read)
                    if not chunk:
                        break
                    writer.write(chunk)
                    await writer.drain()
                    sent_bytes += len(chunk)
        except (ConnectionResetError, BrokenPipeError, asyncio.CancelledError):
            pass

    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass


async def main() -> None:
    parser = argparse.ArgumentParser(description="Khartoum Al-Azhari Single-Port Web + WebSocket Bridge Server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="HTTP + /ws port (default: 8080)")
    parser.add_argument("--ws-host", default="127.0.0.1", help="Godot WebSocket server host (default: 127.0.0.1)")
    parser.add_argument("--ws-port", type=int, default=7778, help="Godot WebSocket server port (default: 7778)")
    parser.add_argument("--web-dir", default=str(WEB_DIR), help="Path to exported web build directory")
    args = parser.parse_args()

    web_dir = Path(args.web_dir)
    web_dir.mkdir(parents=True, exist_ok=True)
    prewarm_web_dir_gzip(web_dir)

    lan_ip = get_lan_ip()
    server = await asyncio.start_server(
        lambda r, w: _handle_client(r, w, web_dir, args.ws_host, args.ws_port),
        host=args.host,
        port=args.port,
    )

    print("=================================================================")
    print(" Khartoum Al-Azhari — Web + WebSocket Bridge Server (Gzip + Cache)")
    print(f" Serving Web Build : {web_dir}")
    print(f" Local PC URL      : http://127.0.0.1:{args.port}")
    print(f" iPhone Safari URL : http://{lan_ip}:{args.port}")
    print(f" WebSocket Proxy   : ws://{lan_ip}:{args.port}/ws -> {args.ws_host}:{args.ws_port}")
    print("=================================================================")

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[host_web_server] Stopped.")
