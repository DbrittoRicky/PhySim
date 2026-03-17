# ==============================================================
# SONATA I — Module 6: Inference Server
# sonata_server.py
#
# Runs a persistent TCP server on localhost:9876.
# Protocol (little-endian):
#   Request : [N: int32] [N × 10 × 31 × float32]
#   Response: [N: int32] [N ×  3 × 13 × float32]
#
# Start: python sonata_server.py
# Stop:  Ctrl+C  (or kill when Godot closes)
# ==============================================================
import socket, struct, time, os
import numpy as np
import onnxruntime as ort

ONNX_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sonata1.onnx")
HOST      = "127.0.0.1"
PORT      = 9876

CTX_FLOATS  = 10 * 31          # 310 floats per object context
PRED_FLOATS =  3 * 13          # 39 floats per object prediction


def recv_exact(conn: socket.socket, n_bytes: int) -> bytes:
    """Blocking receive that guarantees exactly n_bytes are returned."""
    buf = bytearray()
    while len(buf) < n_bytes:
        chunk = conn.recv(n_bytes - len(buf))
        if not chunk:
            raise ConnectionResetError("Godot disconnected mid-transfer")
        buf.extend(chunk)
    return bytes(buf)


def load_session():
    providers = []
    available = [p for p in ort.get_available_providers()]
    if "CUDAExecutionProvider" in available:
        providers.append("CUDAExecutionProvider")
        print(f"  ORT provider : CUDA")
    providers.append("CPUExecutionProvider")
    sess = ort.InferenceSession(ONNX_PATH, providers=providers)
    # Warmup
    dummy = np.zeros((1, 10, 31), dtype=np.float32)
    for _ in range(10):
        sess.run(["prediction"], {"context": dummy})
    return sess


def handle_client(conn: socket.socket, sess: ort.InferenceSession):
    print("  Godot connected.")
    frame_times = []
    n_frames    = 0

    try:
        while True:
            # ── Read header ──
            header = recv_exact(conn, 4)
            n_objects = struct.unpack("<i", header)[0]
            if n_objects <= 0:
                continue

            # ── Read context ──
            ctx_bytes = recv_exact(conn, n_objects * CTX_FLOATS * 4)
            ctx = np.frombuffer(ctx_bytes, dtype=np.float32)\
                    .reshape(n_objects, 10, 31)

            # ── Inference ──
            t0   = time.perf_counter()
            pred = sess.run(["prediction"], {"context": ctx})[0]
            ms   = (time.perf_counter() - t0) * 1000

            # ── Send response ──
            resp = struct.pack("<i", n_objects) + \
                   pred.astype(np.float32).tobytes()
            conn.sendall(resp)

            # ── Logging ──
            frame_times.append(ms)
            n_frames += 1
            if n_frames % 300 == 0:   # log every 5 seconds at 60 Hz
                avg_ms = sum(frame_times[-300:]) / 300
                print(f"  Frame {n_frames:>6}  |  objects={n_objects}  "
                      f"|  avg inference {avg_ms:.2f}ms")

    except (ConnectionResetError, BrokenPipeError):
        print("  Godot disconnected.")


def main():
    print("=" * 50)
    print("  SONATA I — Inference Server")
    print("=" * 50)
    print(f"  Loading {os.path.basename(ONNX_PATH)} ...", end=" ", flush=True)
    sess = load_session()
    print("ready")
    print(f"  Listening on {HOST}:{PORT}")
    print(f"  Waiting for Godot...\n")

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((HOST, PORT))
        server.listen(1)
        while True:
            conn, addr = server.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            handle_client(conn, sess)  # blocks until Godot disconnects
            conn.close()


if __name__ == "__main__":
    main()
