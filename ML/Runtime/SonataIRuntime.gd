# ML/Runtime/SonataIRuntime.gd
# Single-object surrogate. One instance per solo RigidBody3D.
# Call initialize() once, then step() every _physics_process tick.

class_name SonataIRuntime
extends RefCounted

const WINDOW   : int = 10
const HORIZON  : int = 3
const NTARGET  : int = 13   # pos3 + quat4 + linvel3 + angvel3
const JOLT_RESYNC_EVERY : int = HORIZON + 1   # 4

# ── Norm stats ─────────────────────────────────────────────────────────────────
var _ctx_mean  : PackedFloat32Array   # [NTARGET]
var _ctx_std   : PackedFloat32Array
var _tgt_mean  : PackedFloat32Array
var _tgt_std   : PackedFloat32Array

# ── References ─────────────────────────────────────────────────────────────────
var _ml  : Node           # MLManager autoload
var _obj : RigidBody3D

# ── Ring buffer ─────────────────────────────────────────────────────────────────
var _ring      : PackedFloat32Array   # [WINDOW × NTARGET]
var _ring_head : int = 0
var _seen      : int = 0
var _cycle     : int = 0

# ── Public ──────────────────────────────────────────────────────────────────────
func initialize(ml: Node, obj: RigidBody3D,
				stats_path: String = "res://ML/NormStats/normstats_sonata1.json") -> bool:
	_ml  = ml
	_obj = obj
	if not _load_stats(stats_path):
		push_error("SonataIRuntime: failed to load stats from %s" % stats_path)
		return false
	_reset()
	return true

func step() -> bool:
	if not _ml or not _obj: return false
	_cycle = (_cycle + 1) % JOLT_RESYNC_EVERY

	if _cycle == 0:
		# ── Jolt resync tick ───────────────────────────────────────────────────
		_obj.freeze = false
		_reset()          # refill ring from live state over next WINDOW frames
		return false

	# ── ML tick ───────────────────────────────────────────────────────────────
	_obj.freeze = true
	_push(_build_frame())
	if _seen < WINDOW: return false

	var pred : PackedFloat32Array= _ml.run_sonata1(_assemble())    # [WINDOW × NTARGET]
	if pred.is_empty(): return false

	# Step 0 of the 3-step horizon
	_apply(pred.slice(0, NTARGET))
	return true

# ── Frame assembly ─────────────────────────────────────────────────────────────
func _build_frame() -> PackedFloat32Array:
	var p  := _obj.global_position
	var q  := _obj.global_transform.basis.get_rotation_quaternion()
	var lv := _obj.linear_velocity
	var av := _obj.angular_velocity
	var raw := PackedFloat32Array([
		p.x,  p.y,  p.z,
		q.w,  q.x,  q.y,  q.z,
		lv.x, lv.y, lv.z,
		av.x, av.y, av.z
	])
	var out := PackedFloat32Array(); out.resize(NTARGET)
	for i in range(NTARGET):
		out[i] = (raw[i] - _ctx_mean[i]) / maxf(_ctx_std[i], 1e-8)
	return out

func _assemble() -> PackedFloat32Array:
	var ctx := PackedFloat32Array(); ctx.resize(WINDOW * NTARGET)
	for t in range(WINDOW):
		var slot := (_ring_head + t) % WINDOW
		for f in range(NTARGET):
			ctx[t * NTARGET + f] = _ring[slot * NTARGET + f]
	return ctx

func _apply(step_pred: PackedFloat32Array) -> void:
	var px  := step_pred[0]  * _tgt_std[0]  + _tgt_mean[0]
	var py  := step_pred[1]  * _tgt_std[1]  + _tgt_mean[1]
	var pz  := step_pred[2]  * _tgt_std[2]  + _tgt_mean[2]
	var qw  := step_pred[3]  * _tgt_std[3]  + _tgt_mean[3]
	var qx  := step_pred[4]  * _tgt_std[4]  + _tgt_mean[4]
	var qy  := step_pred[5]  * _tgt_std[5]  + _tgt_mean[5]
	var qz  := step_pred[6]  * _tgt_std[6]  + _tgt_mean[6]
	var lvx := step_pred[7]  * _tgt_std[7]  + _tgt_mean[7]
	var lvy := step_pred[8]  * _tgt_std[8]  + _tgt_mean[8]
	var lvz := step_pred[9]  * _tgt_std[9]  + _tgt_mean[9]
	var avx := step_pred[10] * _tgt_std[10] + _tgt_mean[10]
	var avy := step_pred[11] * _tgt_std[11] + _tgt_mean[11]
	var avz := step_pred[12] * _tgt_std[12] + _tgt_mean[12]

	var q   := Quaternion(qx, qy, qz, qw).normalized()
	var rid := _obj.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis(q), Vector3(px, py, pz)))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
		Vector3(lvx, lvy, lvz))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
		Vector3(avx, avy, avz))

# ── Ring buffer helpers ─────────────────────────────────────────────────────────
func _reset() -> void:
	_ring = PackedFloat32Array(); _ring.resize(WINDOW * NTARGET); _ring.fill(0.0)
	_ring_head = 0; _seen = 0; _cycle = 0

func _push(frame: PackedFloat32Array) -> void:
	var base := _ring_head * NTARGET
	for i in range(NTARGET): _ring[base + i] = frame[i]
	_ring_head = (_ring_head + 1) % WINDOW
	_seen = mini(_seen + 1, WINDOW)

func _load_stats(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SonataIRuntime: cannot open %s" % path)
		return false
	var j : Dictionary = JSON.parse_string(f.get_as_text())
	if j.is_empty():
		push_error("SonataIRuntime: empty or malformed JSON at %s" % path)
		return false

	var dyn : Dictionary = j["dynamic_features"]
	_ctx_mean = PackedFloat32Array(Array(dyn["mean"]).slice(0, NTARGET))
	_ctx_std  = PackedFloat32Array(Array(dyn["std"]).slice(0, NTARGET))

	# For Sonata-I the target is the same 13-channel state vector,
	# so target stats == context stats (same distribution)
	_tgt_mean = _ctx_mean.duplicate()
	_tgt_std  = _ctx_std.duplicate()
	return true
