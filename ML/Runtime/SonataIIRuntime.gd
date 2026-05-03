# ML/Runtime/SonataIIRuntime.gd
# Multi-object surrogate for ground-regime clusters (up to 6 objects).
# One instance per cluster. Call initialize() once, step() every physics tick.

class_name SonataIIRuntime
extends RefCounted

const NMAX    : int = 6
const WINDOW  : int = 10
const HORIZON : int = 3
const NTARGET : int = 13
const NDYN    : int = 20    # 13 core state + 7 zero-padding
const NNBR    : int = 7     # centroid_offset(3) + rel_vel(3) + mean_dist(1)
const NCTX    : int = 27    # NDYN + NNBR — per object per frame
const NSTATIC : int = 11    # per-object static features
const NSCENE  : int = 3     # gravity xyz
const JOLT_RESYNC_EVERY : int = HORIZON + 1   # 4

# ── Norm stats ─────────────────────────────────────────────────────────────────
var _ss_mean  : PackedFloat32Array   # scene_static  [NSCENE]
var _ss_std   : PackedFloat32Array
var _os_mean  : PackedFloat32Array   # obj_static    [NSTATIC]
var _os_std   : PackedFloat32Array
var _dyn_mean : PackedFloat32Array   # obj_dynamic   [NDYN]
var _dyn_std  : PackedFloat32Array
var _nbr_mean : PackedFloat32Array   # neighbourhood [NNBR]
var _nbr_std  : PackedFloat32Array
var _tgt_mean : PackedFloat32Array   # target        [NTARGET]
var _tgt_std  : PackedFloat32Array

# ── References ─────────────────────────────────────────────────────────────────
var _ml       : Node
var _objects  : Array       # Array[RigidBody3D], len ≤ NMAX
var _gravity  : Vector3
var _mask     : PackedFloat32Array   # [NMAX]  1.0=active  0.0=padded

# ── Cached obj_static (constant per scenario) ──────────────────────────────────
var _obj_static_norm : PackedFloat32Array   # [NMAX × NSTATIC]

# ── Ring buffer ─────────────────────────────────────────────────────────────────
var _ring      : PackedFloat32Array   # [WINDOW × NMAX × NCTX]
var _ring_head : int = 0
var _seen      : int = 0
var _cycle     : int = 0

# ── Public ──────────────────────────────────────────────────────────────────────
func initialize(ml: Node, objects: Array, gravity: Vector3,
				stats_path: String = "res://ML/NormStats/normstats_sonata2.json") -> bool:
	_ml      = ml
	_objects = objects.slice(0, NMAX)
	_gravity = gravity
	if not _load_stats(stats_path):
		push_error("SonataIIRuntime: failed to load stats from %s" % stats_path)
		return false
	_build_mask()
	_build_obj_static_norm()
	_full_reset()
	return true

func step() -> bool:
	if not _ml or _objects.is_empty(): return false
	_cycle = (_cycle + 1) % JOLT_RESYNC_EVERY

	if _cycle == 0:
		_unfreeze()
		_reset()
		return false

	_freeze()
	_push(_build_ctx_frame())
	if _seen < WINDOW: return false

	var ss   := _build_scene_static_norm()        # [NSCENE]
	var ctx  := _assemble_context()               # [WINDOW × NMAX × NCTX]
	var pred : PackedFloat32Array = _ml.run_sonata2(ss, _obj_static_norm, ctx, _mask)

	if pred.is_empty(): return false
	_apply(_extract_step(pred, 0))   # step 0 of the 3-horizon prediction
	return true

# ── Context frame builder ──────────────────────────────────────────────────────
func _build_ctx_frame() -> PackedFloat32Array:
	var frame := PackedFloat32Array()
	frame.resize(NMAX * NCTX)
	frame.fill(0.0)

	# Precompute world positions and velocities for neighbourhood stats
	var wpos : Array = []   # Vector3 per slot
	var wvel : Array = []
	for i in range(NMAX):
		if i < _objects.size() and _mask[i] > 0.5:
			var o := _objects[i] as RigidBody3D
			wpos.append(o.global_position)
			wvel.append(o.linear_velocity)
		else:
			wpos.append(Vector3.ZERO)
			wvel.append(Vector3.ZERO)

	# Scene centroid and mean velocity (active slots only)
	var n_active : int = 0
	var centroid := Vector3.ZERO
	var mean_vel := Vector3.ZERO
	for i in range(NMAX):
		if _mask[i] > 0.5:
			centroid += wpos[i]
			mean_vel += wvel[i]
			n_active += 1
	if n_active > 0:
		centroid /= float(n_active)
		mean_vel /= float(n_active)

	for i in range(NMAX):
		if _mask[i] < 0.5: continue   # padded slot stays zero
		var obj := _objects[i] as RigidBody3D
		var base := i * NCTX

		# ── NDYN block (0..19): 13 core state + 7 zeros ──────────────────────
		var p  := obj.global_position
		var q  := obj.global_transform.basis.get_rotation_quaternion()
		var lv := obj.linear_velocity
		var av := obj.angular_velocity
		var core := PackedFloat32Array([
			p.x,  p.y,  p.z,
			q.w,  q.x,  q.y,  q.z,
			lv.x, lv.y, lv.z,
			av.x, av.y, av.z
		])
		for f in range(NTARGET):
			frame[base + f] = (core[f] - _dyn_mean[f]) / maxf(_dyn_std[f], 1e-8)
		# Channels 13–19 remain 0.0 (padding already done by fill)

		# ── NNBR block (20..26): neighbourhood summary ────────────────────────
		var co  : Vector3= wpos[i] - centroid                   # centroid offset (3)
		var rv  : Vector3= wvel[i] - mean_vel                   # relative velocity (3)
		var md  := _mean_dist(i, wpos)                  # mean inter-object dist (1)
		var nbr := PackedFloat32Array([co.x, co.y, co.z, rv.x, rv.y, rv.z, md])
		for f in range(NNBR):
			frame[base + NDYN + f] = (nbr[f] - _nbr_mean[f]) / maxf(_nbr_std[f], 1e-8)

	return frame

func _mean_dist(idx: int, wpos: Array) -> float:
	var total : float = 0.0
	var n     : int   = 0
	for j in range(NMAX):
		if j != idx and _mask[j] > 0.5:
			total += wpos[idx].distance_to(wpos[j])
			n += 1
	return total / float(max(n, 1))

# ── Ring buffer ─────────────────────────────────────────────────────────────────
func _reset() -> void:
	_ring = PackedFloat32Array()
	_ring.resize(WINDOW * NMAX * NCTX)
	_ring.fill(0.0)
	_ring_head = 0
	_seen = 0
	
func _full_reset() -> void:
	_cycle = 0
	_reset()

func _push(frame: PackedFloat32Array) -> void:
	var base := _ring_head * NMAX * NCTX
	for i in range(NMAX * NCTX): _ring[base + i] = frame[i]
	_ring_head = (_ring_head + 1) % WINDOW
	_seen = mini(_seen + 1, WINDOW)

func _assemble_context() -> PackedFloat32Array:
	var ctx := PackedFloat32Array()
	ctx.resize(WINDOW * NMAX * NCTX)
	for t in range(WINDOW):
		var src := (_ring_head + t) % WINDOW
		for i in range(NMAX * NCTX):
			ctx[t * NMAX * NCTX + i] = _ring[src * NMAX * NCTX + i]
	return ctx

# ── Prediction apply ────────────────────────────────────────────────────────────
# pred: flat [NMAX × HORIZON × NTARGET], step=0 returns [NMAX × NTARGET]
func _extract_step(pred: PackedFloat32Array, step: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(NMAX * NTARGET)
	for i in range(NMAX):
		var src := i * HORIZON * NTARGET + step * NTARGET
		var dst := i * NTARGET
		for f in range(NTARGET): out[dst + f] = pred[src + f]
	return out

func _apply(step_pred: PackedFloat32Array) -> void:
	for i in range(_objects.size()):
		if _mask[i] < 0.5: continue
		var obj := _objects[i] as RigidBody3D
		var b   := i * NTARGET
		var px  := step_pred[b+0]  * _tgt_std[0]  + _tgt_mean[0]
		var py  := step_pred[b+1]  * _tgt_std[1]  + _tgt_mean[1]
		var pz  := step_pred[b+2]  * _tgt_std[2]  + _tgt_mean[2]
		var qw  := step_pred[b+3]  * _tgt_std[3]  + _tgt_mean[3]
		var qx  := step_pred[b+4]  * _tgt_std[4]  + _tgt_mean[4]
		var qy  := step_pred[b+5]  * _tgt_std[5]  + _tgt_mean[5]
		var qz  := step_pred[b+6]  * _tgt_std[6]  + _tgt_mean[6]
		var lvx := step_pred[b+7]  * _tgt_std[7]  + _tgt_mean[7]
		var lvy := step_pred[b+8]  * _tgt_std[8]  + _tgt_mean[8]
		var lvz := step_pred[b+9]  * _tgt_std[9]  + _tgt_mean[9]
		var avx := step_pred[b+10] * _tgt_std[10] + _tgt_mean[10]
		var avy := step_pred[b+11] * _tgt_std[11] + _tgt_mean[11]
		var avz := step_pred[b+12] * _tgt_std[12] + _tgt_mean[12]
		var q   := Quaternion(qx, qy, qz, qw).normalized()
		var rid := obj.get_rid()
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(q), Vector3(px, py, pz)))
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
			Vector3(lvx, lvy, lvz))
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
			Vector3(avx, avy, avz))

# ── Scene static ────────────────────────────────────────────────────────────────
func _build_scene_static_norm() -> PackedFloat32Array:
# scene_static channels: [env_state_binary, air_drag_coefficient, n_objects]
# env_state_binary = 0 (ground regime, no fluid)
	var air_drag : float = 0.0
	if Engine.has_singleton("EnvironmentManager"):
		air_drag = EnvironmentManager.get_drag_coefficient()
	var n_obj := float(_objects.size())
	var ss := PackedFloat32Array([0.0, air_drag, n_obj])
	for i in range(NSCENE):
		ss[i] = (ss[i] - _ss_mean[i]) / maxf(_ss_std[i], 1e-8)
	return ss

# ── obj_static (constant per scenario) ─────────────────────────────────────────
func _build_obj_static_norm() -> void:
	_obj_static_norm = PackedFloat32Array()
	_obj_static_norm.resize(NMAX * NSTATIC)
	_obj_static_norm.fill(0.0)
	for i in range(_objects.size()):
		if _mask[i] < 0.5: continue
		var obj  := _objects[i] as RigidBody3D
		var raw  := _extract_obj_static_raw(obj)
		var base := i * NSTATIC
		for f in range(NSTATIC):
			_obj_static_norm[base + f] = (raw[f] - _os_mean[f]) / maxf(_os_std[f], 1e-8)

func _extract_obj_static_raw(obj: RigidBody3D) -> PackedFloat32Array:
	# Features: mass(1) gravity_scale(1) gravity_mag(1) friction(1) bounce(1)
	#           linear_damp(1) angular_damp(1) shape_type_int(1) dim_primary(1)
	#           dim_secondary(1) env_state_binary(1)  →  11 total
	return PackedFloat32Array([
		obj.mass,
		obj.gravity_scale,
		_gravity.length(),
		obj.physics_material_override.friction if obj.physics_material_override else 0.0,
		obj.physics_material_override.bounce   if obj.physics_material_override else 0.0,
		obj.linear_damp,
		obj.angular_damp,
		float(obj.get_meta("shape_type_int", 0)),
		float(obj.get_meta("dim_primary",    0.0)),
		float(obj.get_meta("dim_secondary",  0.0)),
		0.0   # env_state_binary — always 0 for Sonata-II (ground regime)
	])

# ── Mask & freeze helpers ───────────────────────────────────────────────────────
func _build_mask() -> void:
	_mask = PackedFloat32Array(); _mask.resize(NMAX); _mask.fill(0.0)
	for i in range(min(_objects.size(), NMAX)): _mask[i] = 1.0

func _freeze() -> void:
	for obj in _objects:
		var rb := obj as RigidBody3D
		if is_instance_valid(rb):
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true

func _unfreeze() -> void:
	for obj in _objects:
		var rb := obj as RigidBody3D
		if is_instance_valid(rb): rb.freeze = false

# ── Stats loader ────────────────────────────────────────────────────────────────
func _load_stats(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SonataIIRuntime: cannot open %s" % path)
		return false
	var j : Dictionary = JSON.parse_string(f.get_as_text())
	if j.is_empty():
		push_error("SonataIIRuntime: malformed JSON at %s" % path)
		return false

	_ss_mean  = PackedFloat32Array(j["scene_static"]["mean"])
	_ss_std   = PackedFloat32Array(j["scene_static"]["std"])
	_os_mean  = PackedFloat32Array(j["obj_static"]["mean"])
	_os_std   = PackedFloat32Array(j["obj_static"]["std"])
	
	var dyn : Dictionary = j["obj_dynamic"]
	_dyn_mean = PackedFloat32Array(dyn["mean"])  
	_dyn_std  = PackedFloat32Array(dyn["std"])  
	
	_nbr_mean = PackedFloat32Array(j["pairwise"]["mean"])   
	_nbr_std  = PackedFloat32Array(j["pairwise"]["std"])    
	
	_tgt_mean = PackedFloat32Array(Array(dyn["mean"]).slice(0, NTARGET))
	_tgt_std  = PackedFloat32Array(Array(dyn["std"]).slice(0, NTARGET))
	return true
	
