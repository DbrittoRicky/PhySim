extends Node

# ─────────────────────────────────────────────────────────────────────────────
# MLManager.gd
# Sonata-I  → ONNXLoader plugin (single-input, synchronous)
# Sonata-II → Python FastAPI server (multi-input, async HTTP)
# ─────────────────────────────────────────────────────────────────────────────

const SERVER_URL    := "http://127.0.0.1:7842"
const SERVER_SCRIPT := "ML/server/physim_inference_server.py"
const PATH_S1       := "res://ML/Models/sonata1.onnx"

# ── Sonata-I: plugin session ──────────────────────────────────────────────────
var _session_s1 : ONNXLoader

# ── Sonata-II: HTTP nodes ─────────────────────────────────────────────────────
var _http_s2   : HTTPRequest
var _http_ping : HTTPRequest

var _pending_s2  : Callable = Callable()
var server_ready := false
var _server_pid  := -1

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Sonata-I — plugin
	_session_s1 = ONNXLoader.new()
	add_child(_session_s1)
	_session_s1.load_model(ProjectSettings.globalize_path(PATH_S1))
	print("[MLManager] Sonata-I loaded via plugin.")

	# Sonata-II — HTTP
	_http_s2   = HTTPRequest.new()
	_http_ping = HTTPRequest.new()
	add_child(_http_s2)
	add_child(_http_ping)
	_http_s2.request_completed.connect(_on_s2_complete)
	_http_ping.request_completed.connect(_on_ping_complete)

	_launch_server()


func _exit_tree() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		print("[MLManager] Server process killed.")


# ── Server lifecycle ──────────────────────────────────────────────────────────

func _launch_server() -> void:
	var script := ProjectSettings.globalize_path("res://" + SERVER_SCRIPT)
	_server_pid = OS.create_process("python", [script])
	print("[MLManager] Server PID: ", _server_pid, " — polling for readiness...")
	_poll_ping()


func _poll_ping() -> void:
	await get_tree().create_timer(1.5).timeout
	if _http_ping.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_http_ping.request(SERVER_URL + "/ping")


func _on_ping_complete(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		server_ready = true
		print("[MLManager] Sonata-II server ready.")
	else:
		print("[MLManager] Server not ready yet, retrying...")
		_poll_ping()


# ── Sonata-I: synchronous via plugin ─────────────────────────────────────────

func run_sonata1(context: PackedFloat32Array) -> PackedFloat32Array:
	var result: Array = _session_s1.predict([context])
	if result.is_empty():
		push_error("[MLManager] Sonata-I returned empty.")
		return PackedFloat32Array()
	return PackedFloat32Array(result[0])


# ── Sonata-II: async via HTTP ─────────────────────────────────────────────────

func run_sonata2_async(
	scene_static : PackedFloat32Array,
	obj_static   : PackedFloat32Array,
	context      : PackedFloat32Array,
	obj_mask     : PackedFloat32Array,
	on_complete  : Callable
) -> void:
	if not server_ready:
		return
	if _http_s2.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return  # previous request still in flight, skip this tick

	_pending_s2 = on_complete

	var body := JSON.stringify({
		"scene_static" : Array(scene_static),
		"obj_static"   : Array(obj_static),
		"context"      : Array(context),
		"obj_mask"     : Array(obj_mask)
	})

	_http_s2.request(
		SERVER_URL + "/predict_s2",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)


func _on_s2_complete(
	_result  : int,
	code     : int,
	_headers : PackedStringArray,
	body     : PackedByteArray
) -> void:
	if code != 200:
		push_error("[MLManager] Sonata-II server returned code: " + str(code))
		_pending_s2 = Callable()
		return
	if not _pending_s2.is_valid():
		return

	var j : Dictionary = JSON.parse_string(body.get_string_from_utf8())
	_pending_s2.call(PackedFloat32Array(j["prediction"]))
	_pending_s2 = Callable()
