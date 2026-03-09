# ==============================================================
# SONATA I — Module 6: Godot Inference Client
# SonataPredictor.gd  →  Add as Autoload singleton
#
# Manages the TCP connection to sonata_server.py.
# Batches ALL registered SonataBody contexts into ONE request
# per physics frame, then distributes predictions back.
# ==============================================================
extends Node

const HOST         := "127.0.0.1"
const PORT         := 9876
const CTX_FLOATS   := 10 * 31    # per object
const PRED_FLOATS  := 3  * 13    # per object
const CONNECT_TIMEOUT_MS := 5000

var _peer    : StreamPeerTCP = null
var _bodies  : Array = []          # registered SonataBody nodes
var _connected := false


# ── Lifecycle ─────────────────────────────────────────────────
func _ready() -> void:
	set_physics_process(false)
	call_deferred("_connect_to_server")


func _connect_to_server() -> void:
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(HOST, PORT)
	if err != OK:
		push_error("SonataPredictor: cannot initiate TCP connect (err=%d)" % err)
		return

	# Poll until connected or timeout
	var t0 := Time.get_ticks_msec()
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_peer.poll()
		if Time.get_ticks_msec() - t0 > CONNECT_TIMEOUT_MS:
			push_error("SonataPredictor: connection timeout — is sonata_server.py running?")
			return
		OS.delay_msec(5)

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		push_error("SonataPredictor: failed to connect to %s:%d" % [HOST, PORT])
		return

	_peer.set_no_delay(true)
	_connected = true
	set_physics_process(true)
	print("SonataPredictor: connected to inference server ✓")


# ── Registration ──────────────────────────────────────────────
func register(body: Node) -> void:
	if body not in _bodies:
		_bodies.append(body)

func unregister(body: Node) -> void:
	_bodies.erase(body)


# ── Main physics loop ─────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not _connected or _bodies.is_empty():
		return

	# ── 1. Collect ready bodies ──
	var ready_bodies : Array = []
	for body in _bodies:
		if body.is_ready_for_inference():
			ready_bodies.append(body)

	if ready_bodies.is_empty():
		return

	var n := ready_bodies.size()

	# ── 2. Build batched context: (N × 310 float32) ──
	var ctx_buf := PackedFloat32Array()
	ctx_buf.resize(n * CTX_FLOATS)
	for i in range(n):
		var body_ctx : PackedFloat32Array= ready_bodies[i].get_context()  # PackedFloat32Array(310,)
		for j in range(CTX_FLOATS):
			ctx_buf[i * CTX_FLOATS + j] = body_ctx[j]

	# ── 3. Send request: [N: int32][N*310 float32] ──
	var request := PackedByteArray()
	request.resize(4 + n * CTX_FLOATS * 4)
	request.encode_s32(0, n)
	var raw_ctx := ctx_buf.to_byte_array()
	for i in range(raw_ctx.size()):
		request[4 + i] = raw_ctx[i]
	_peer.put_data(request)

	# ── 4. Receive response: [N: int32][N*39 float32] ──
	var response_size := 4 + n * PRED_FLOATS * 4
	var resp_bytes    := _recv_exact(response_size)
	if resp_bytes.is_empty():
		return

	var n_resp := resp_bytes.decode_s32(0)
	if n_resp != n:
		push_warning("SonataPredictor: expected %d predictions, got %d" % [n, n_resp])
		return

	var pred_bytes := resp_bytes.slice(4)
	var pred_buf   := pred_bytes.to_float32_array()   # (N × 39,)

	# ── 5. Distribute predictions ──
	for i in range(n):
		var pred_i := pred_buf.slice(i * PRED_FLOATS, (i + 1) * PRED_FLOATS)
		ready_bodies[i].apply_prediction(pred_i)


# ── Reliable receive ──────────────────────────────────────────
func _recv_exact(n_bytes: int) -> PackedByteArray:
	var buf := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 50   # 50ms max wait per frame

	while buf.size() < n_bytes:
		_peer.poll()
		var available := _peer.get_available_bytes()
		if available > 0:
			var chunk_size : int = min(available, n_bytes - buf.size())
			var result     := _peer.get_data(chunk_size)
			if result[0] == OK:
				buf.append_array(result[1])
		elif Time.get_ticks_msec() > deadline:
			push_error("SonataPredictor: receive timeout")
			return PackedByteArray()

	return buf


# ── Cleanup ───────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _peer != null:
		_peer.disconnect_from_host()
