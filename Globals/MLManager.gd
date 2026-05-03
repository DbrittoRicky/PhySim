# Globals/MLManager.gd
# Central ONNX session registry. Autoloaded singleton.
# Uses mat490/Godot-ONNX-AI-Models-Loaders plugin (ONNXLoader node).
# Exposes run_sonata1() and run_sonata2() — called exclusively by
# their respective Runtime wrappers, never by scene scripts directly.

extends Node

const _PATH_S1 := "res://ML/Models/sonata1.onnx"
const _PATH_S2 := "res://ML/Models/sonata2.onnx"

var _session_s1: ONNXLoader
var _session_s2: ONNXLoader

func _ready() -> void:
	_session_s1 = ONNXLoader.new()
	_session_s2 = ONNXLoader.new()
	add_child(_session_s1)
	add_child(_session_s2)
	_session_s1.load_model(ProjectSettings.globalize_path(_PATH_S1))
	_session_s2.load_model(ProjectSettings.globalize_path(_PATH_S2))
	print("[MLManager] Sonata-I and Sonata-II sessions loaded.")

# ── Sonata-I ───────────────────────────────────────────────────────────────────
# Input:  context  PackedFloat32Array  flat [1, 10, 13]
# Output: PackedFloat32Array           flat [1, 3, 13]
func run_sonata1(context: PackedFloat32Array) -> PackedFloat32Array:
	var result: Array = _session_s1.predict([context])
	if result.is_empty():
		push_error("[MLManager] Sonata-I inference returned empty result.")
		return PackedFloat32Array()
	return PackedFloat32Array(result[0])

# ── Sonata-II ──────────────────────────────────────────────────────────────────
# Inputs (all flat, batch=1):
#   scene_static  [1, 3]
#   obj_static    [1, NMAX, 11]
#   context       [1, WINDOW, NMAX, 27]   (NDYN=20 + NNBR=7)
#   obj_mask      [1, NMAX]
# Output: PackedFloat32Array  flat [1, NMAX, 3, 13]
func run_sonata2(
	scene_static : PackedFloat32Array,
	obj_static   : PackedFloat32Array,
	context      : PackedFloat32Array,
	obj_mask     : PackedFloat32Array
) -> PackedFloat32Array:
	var result: Array = _session_s2.predict([
		scene_static,
		obj_static,
		context,
		obj_mask
	])
	if result.is_empty():
		push_error("[MLManager] Sonata-II inference returned empty result.")
		return PackedFloat32Array()
	return PackedFloat32Array(result[0])
