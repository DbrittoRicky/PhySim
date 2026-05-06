# SONATA II Runtime Inference Wrapper
# Path: res://PhySim/Runtime/Sonata2/sonata2runtime.gd
#
# Assembles neighbourhood tensor from live PhysicsServer3D state,
# maintains the 10-frame ring buffer, normalizes inputs, dispatches
# to MLManager (async HTTP), denormalizes outputs, and writes predicted
# object states back to RigidBody3D nodes.
#
# MLManager interface:
#   MLManager.run_sonata2_async(
#       scene_static  : PackedFloat32Array,  # flat [3]
#       obj_static    : PackedFloat32Array,  # flat [NMAX * 11]
#       context       : PackedFloat32Array,  # flat [WINDOW * NMAX * 27]
#       obj_mask      : PackedFloat32Array,  # flat [NMAX]
#       on_complete   : Callable             # receives PackedFloat32Array
#   ) -> void

class_name SonataIIRuntime
extends RefCounted

# ── Model constants — must match sonata2gru.py ────────────────────────────────
const NMAX    : int = 6    # object slots (padded)
const WINDOW  : int = 10   # history frames fed to GRU
const HORIZON : int = 3    # frames predicted per call
const NTARGET : int = 13   # pos(3) + quat(4) + linvel(3) + angvel(3)
const NDYN    : int = 20   # objdynamic width (NTARGET + 7 zeros)
const NNBR    : int = 7    # neighbourhood width
const NCTX    : int = 27   # NDYN + NNBR, context width per object per frame
const NSTATIC : int = 11   # objstatic width per object
const NSCENE  : int = 3    # scenestatic width (gravity x, y, z)

# Shape key one-hot index — order must match training preprocessing
const SHAPE_ORDER : Array = ["SPHERE","CUBE","CYLINDER","CAPSULE","CUBOID","PRISM"]

# 3-predict-1-Jolt cycle: run ML for HORIZON frames, then let Jolt run 1 frame
const JOLT_RESYNC_EVERY : int = HORIZON + 1  # = 4

# ── State ─────────────────────────────────────────────────────────────────────
var _ml_manager  : Node    = null
var _objects     : Array   = []    # Array[RigidBody3D], len <= NMAX
var _mask        : PackedFloat32Array   # NMAX
var _gravity     : Vector3 = Vector3(0.0, -9.8, 0.0)

# ── Normalization stats (loaded from JSON) ────────────────────────────────────
var _nss_mean : PackedFloat32Array   # scenestatic mean  [NSCENE]
var _nss_std  : PackedFloat32Array   # scenestatic std   [NSCENE]
var _nos_mean : PackedFloat32Array   # objstatic mean    [NSTATIC]
var _nos_std  : PackedFloat32Array   # objstatic std     [NSTATIC]
var _ndyn_mean: PackedFloat32Array   # objdynamic mean   [NDYN]
var _ndyn_std : PackedFloat32Array   # objdynamic std    [NDYN]
var _nnbr_mean: PackedFloat32Array   # neighbourhood mean[NNBR]
var _nnbr_std : PackedFloat32Array   # neighbourhood std [NNBR]
var _ntgt_mean: PackedFloat32Array   # target mean       [NTARGET]
var _ntgt_std : PackedFloat32Array   # target std        [NTARGET]

# ── Ring buffer ───────────────────────────────────────────────────────────────
# WINDOW frames of NMAX * NCTX context stored flat.
# Index: frame_slot * NMAX * NCTX + obj_idx * NCTX + feat_idx
var _ring_buf  : PackedFloat32Array  # [WINDOW * NMAX * NCTX]
var _ring_head : int = 0             # next write position (circular, mod WINDOW)
var _frames_seen : int = 0           # frames written so far (<= WINDOW = warm)

# ── Cached objstatic — constant for the lifetime of a scenario ───────────────
var _obj_static_norm : PackedFloat32Array  # [NMAX * NSTATIC]

# ── Prediction state ──────────────────────────────────────────────────────────
var _last_pred : PackedFloat32Array   # [NMAX * NTARGET] last ONNX output
var _cycle_ctr : int = 0

# ── MIGRATION: async guard ────────────────────────────────────────────────────
var _awaiting_prediction : bool = false

# ── Diagnostics ───────────────────────────────────────────────────────────────
var _infer_count  : int = 0
var _resync_count : int = 0

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Call once when the scenario begins or when the object set changes.
## ml_manager  — the autoloaded MLManager node
## gravity     — current scene gravity Vector3 (e.g. Vector3(0,-9.8,0))
## objects     — Array of RigidBody3D, up to NMAX elements
## stats_path  — full path to normstats_sonata2.json
func initialize(
	ml_manager : Node,
	objects    : Array,       # ← moved to slot 2
	gravity    : Vector3,     # ← moved to slot 3
	stats_path : String = "D:/PhySIm/DataGen/training/export_sonata2/normstatssonata2.json"
) -> bool:
	_ml_manager = ml_manager
	_objects    = objects.slice(0, NMAX)
	_gravity    = gravity

	if not _load_norm_stats(stats_path):
		push_error("SonataIIRuntime: failed to load norm stats from: " + stats_path)
		return false

	_build_mask()
	_build_obj_static_norm()
	_reset_ring_buffer()

	print("SonataIIRuntime: objects=%d gravity=(%.2f,%.2f,%.2f)" % [
		_objects.size(), _gravity.x, _gravity.y, _gravity.z
	])
	return true


## Call every _physics_process tick while SONATA-II governs the objects.
## Returns true when an ONNX inference was dispatched this tick.
func step() -> bool:
	if _ml_manager == null or _objects.is_empty():
		return false

	_cycle_ctr = (_cycle_ctr + 1) % JOLT_RESYNC_EVERY

	# ── Jolt resync frame: unfreeze, let Jolt run, push real state ────────────
	if _cycle_ctr == 0:
		_unfreeze_objects()
		_resync_from_jolt()
		_resync_count += 1
		return false

	# ── ML tick ───────────────────────────────────────────────────────────────
	_freeze_objects()
	_push_ring_frame(_build_context_frame())

	if _frames_seen < WINDOW:
		return false   # ring buffer not warm yet

	# MIGRATION: non-blocking guard
	if _awaiting_prediction:
		return false   # previous request still in flight, skip this tick

	var ss  : PackedFloat32Array = _build_scene_static_norm()
	var ctx : PackedFloat32Array = _assemble_context()

	_awaiting_prediction = true
	_ml_manager.run_sonata2_async(
		ss,
		_obj_static_norm,
		ctx,
		_mask,
		func(pred: PackedFloat32Array) -> void:
			_awaiting_prediction = false
			if pred.is_empty():
				return
			_last_pred = _extract_step(pred, 0)   # first predicted step
			_apply_predictions(_last_pred)
			_infer_count += 1
	)
	return true


## Returns a diagnostic string for HUD/debug output.
func diagnostics() -> String:
	return "SONATA-II inferences=%d resyncs=%d warm=%s" % [
		_infer_count, _resync_count, str(_frames_seen >= WINDOW)
	]


# ─────────────────────────────────────────────────────────────────────────────
# Ring buffer
# ─────────────────────────────────────────────────────────────────────────────

func _reset_ring_buffer() -> void:
	_ring_buf = PackedFloat32Array()
	_ring_buf.resize(WINDOW * NMAX * NCTX)
	_ring_buf.fill(0.0)
	_ring_head   = 0
	_frames_seen = 0
	_last_pred   = PackedFloat32Array()
	_last_pred.resize(NMAX * NTARGET)
	_last_pred.fill(0.0)
	_cycle_ctr           = 0
	_awaiting_prediction = false


## Write one frame of context into the ring buffer.
## ctx_frame: PackedFloat32Array [NMAX * NCTX], already normalized.
func _push_ring_frame(ctx_frame: PackedFloat32Array) -> void:
	var base : int = _ring_head * NMAX * NCTX
	for i in range(NMAX * NCTX):
		_ring_buf[base + i] = ctx_frame[i]
	_ring_head   = (_ring_head + 1) % WINDOW
	_frames_seen = mini(_frames_seen + 1, WINDOW)


## Assemble [WINDOW * NMAX * NCTX] in chronological order from circular buffer.
## _ring_head points to the NEXT write slot, so oldest = _ring_head.
func _assemble_context() -> PackedFloat32Array:
	var ctx : PackedFloat32Array
	ctx.resize(WINDOW * NMAX * NCTX)
	for w in range(WINDOW):
		var src_slot : int = (_ring_head + w) % WINDOW
		var src_base : int = src_slot * NMAX * NCTX
		var dst_base : int = w * NMAX * NCTX
		for i in range(NMAX * NCTX):
			ctx[dst_base + i] = _ring_buf[src_base + i]
	return ctx


# ─────────────────────────────────────────────────────────────────────────────
# Context frame assembly
# ─────────────────────────────────────────────────────────────────────────────

## Builds the current context frame [NMAX * NCTX] from live Jolt state.
func _build_context_frame() -> PackedFloat32Array:
	var frame : PackedFloat32Array
	frame.resize(NMAX * NCTX)
	frame.fill(0.0)

	# Collect world-space positions and velocities for neighbourhood computation
	var world_pos : Array = []   # Vector3 per slot
	var world_vel : Array = []   # Vector3 per slot
	for i in range(NMAX):
		if i < _objects.size() and _mask[i] > 0.5:
			var obj := _objects[i] as RigidBody3D
			world_pos.append(obj.global_position)
			world_vel.append(obj.linear_velocity)
		else:
			world_pos.append(Vector3.ZERO)
			world_vel.append(Vector3.ZERO)

	# Scene centroid and mean velocity over active objects
	var active_n  : int     = 0
	var centroid  : Vector3 = Vector3.ZERO
	var mean_vel  : Vector3 = Vector3.ZERO
	for i in range(NMAX):
		if _mask[i] > 0.5:
			centroid += world_pos[i]
			mean_vel += world_vel[i]
			active_n += 1
	if active_n > 0:
		centroid /= float(active_n)
		mean_vel /= float(active_n)

	for i in range(NMAX):
		var base : int = i * NCTX
		if _mask[i] < 0.5:
			continue   # empty slot: all zeros, mask signals absence

		var obj := _objects[i] as RigidBody3D

		# ── objdynamic block [0..NDYN] ────────────────────────────────────────
		var pos : Vector3 = obj.global_position
		var rot : Quaternion = obj.global_transform.basis.get_rotation_quaternion()
		var lv  : Vector3 = obj.linear_velocity
		var av  : Vector3 = obj.angular_velocity
		var raw_dyn : PackedFloat32Array = PackedFloat32Array([
			pos.x, pos.y, pos.z,
			rot.w, rot.x, rot.y, rot.z,
			lv.x,  lv.y,  lv.z,
			av.x,  av.y,  av.z,
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0  # 7 zeros pad → NDYN = 20
		])
		for f in range(NDYN):
			frame[base + f] = (raw_dyn[f] - _ndyn_mean[f]) / maxf(_ndyn_std[f], 1e-8)

		# ── neighbourhood block [NDYN..NCTX] ─────────────────────────────────
		var rel_pos : Vector3 = world_pos[i] - centroid
		var rel_vel : Vector3 = world_vel[i] - mean_vel
		var raw_nbr : PackedFloat32Array = PackedFloat32Array([
			rel_pos.x, rel_pos.y, rel_pos.z,
			rel_vel.x, rel_vel.y, rel_vel.z,
			float(active_n)
		])
		for f in range(NNBR):
			frame[base + NDYN + f] = (raw_nbr[f] - _nnbr_mean[f]) / maxf(_nnbr_std[f], 1e-8)

	return frame


# ─────────────────────────────────────────────────────────────────────────────
# Scene-static
# ─────────────────────────────────────────────────────────────────────────────

func _build_scene_static_norm() -> PackedFloat32Array:
	var ss : PackedFloat32Array = PackedFloat32Array([_gravity.x, _gravity.y, _gravity.z])
	for i in range(NSCENE):
		ss[i] = (ss[i] - _nss_mean[i]) / maxf(_nss_std[i], 1e-8)
	return ss


# ─────────────────────────────────────────────────────────────────────────────
# objstatic — built once per scenario
# ─────────────────────────────────────────────────────────────────────────────

func _build_obj_static_norm() -> void:
	_obj_static_norm = PackedFloat32Array()
	_obj_static_norm.resize(NMAX * NSTATIC)
	_obj_static_norm.fill(0.0)

	for i in range(_objects.size()):
		if _mask[i] < 0.5:
			continue
		var obj := _objects[i] as RigidBody3D
		var raw : PackedFloat32Array = _extract_obj_static_raw(obj)
		var base : int = i * NSTATIC
		for f in range(NSTATIC):
			_obj_static_norm[base + f] = (raw[f] - _nos_mean[f]) / maxf(_nos_std[f], 1e-8)


## Extracts raw (un-normalized) objstatic vector [NSTATIC] from a RigidBody3D.
## Feature layout: shape_one_hot(6) + mass_log(1) + friction(1) +
##                 bounce(1) + lin_damp(1) + ang_damp(1)
func _extract_obj_static_raw(obj: RigidBody3D) -> PackedFloat32Array:
	var raw : PackedFloat32Array
	raw.resize(NSTATIC)
	raw.fill(0.0)

	# Shape one-hot [0..5] — read from metadata set by spawner
	var shape_name : String = obj.get_meta("shape_type", "SPHERE")
	var shape_idx  : int    = SHAPE_ORDER.find(shape_name)
	if shape_idx >= 0:
		raw[shape_idx] = 1.0

	# Scalar physics properties [6..10]
	raw[6]  = log(maxf(obj.mass, 1e-3))
	raw[7]  = obj.physics_material_override.friction   if obj.physics_material_override else 0.5
	raw[8]  = obj.physics_material_override.bounce     if obj.physics_material_override else 0.0
	raw[9]  = obj.linear_damp
	raw[10] = obj.angular_damp
	return raw


# ─────────────────────────────────────────────────────────────────────────────
# Mask
# ─────────────────────────────────────────────────────────────────────────────

func _build_mask() -> void:
	_mask = PackedFloat32Array()
	_mask.resize(NMAX)
	_mask.fill(0.0)
	for i in range(mini(_objects.size(), NMAX)):
		if is_instance_valid(_objects[i]):
			_mask[i] = 1.0


# ─────────────────────────────────────────────────────────────────────────────
# Prediction apply / extract
# ─────────────────────────────────────────────────────────────────────────────

## Slice one predicted horizon step from the flat output.
## pred: [NMAX * HORIZON * NTARGET] flat
## Returns [NMAX * NTARGET] for the given horizon index.
func _extract_step(pred: PackedFloat32Array, step: int) -> PackedFloat32Array:
	var out : PackedFloat32Array
	out.resize(NMAX * NTARGET)
	for i in range(NMAX):
		var src_base : int = i * HORIZON * NTARGET + step * NTARGET
		var dst_base : int = i * NTARGET
		for f in range(NTARGET):
			out[dst_base + f] = pred[src_base + f]
	return out


## Denormalize and apply predicted states to the managed RigidBody3D nodes.
## step_pred: [NMAX * NTARGET] in normalized space.
func _apply_predictions(step_pred: PackedFloat32Array) -> void:
	for i in range(_objects.size()):
		if _mask[i] < 0.5:
			continue
		var obj := _objects[i] as RigidBody3D
		var base : int = i * NTARGET

		# Denormalize: x_world = x_norm * std + mean
		var px : float = step_pred[base + 0]  * _ntgt_std[0]  + _ntgt_mean[0]
		var py : float = step_pred[base + 1]  * _ntgt_std[1]  + _ntgt_mean[1]
		var pz : float = step_pred[base + 2]  * _ntgt_std[2]  + _ntgt_mean[2]

		var qw : float = step_pred[base + 3]  * _ntgt_std[3]  + _ntgt_mean[3]
		var qx : float = step_pred[base + 4]  * _ntgt_std[4]  + _ntgt_mean[4]
		var qy : float = step_pred[base + 5]  * _ntgt_std[5]  + _ntgt_mean[5]
		var qz : float = step_pred[base + 6]  * _ntgt_std[6]  + _ntgt_mean[6]

		var lvx : float = step_pred[base + 7]  * _ntgt_std[7]  + _ntgt_mean[7]
		var lvy : float = step_pred[base + 8]  * _ntgt_std[8]  + _ntgt_mean[8]
		var lvz : float = step_pred[base + 9]  * _ntgt_std[9]  + _ntgt_mean[9]

		var avx : float = step_pred[base + 10] * _ntgt_std[10] + _ntgt_mean[10]
		var avy : float = step_pred[base + 11] * _ntgt_std[11] + _ntgt_mean[11]
		var avz : float = step_pred[base + 12] * _ntgt_std[12] + _ntgt_mean[12]

		# Write back into Jolt state
		var q := Quaternion(qx, qy, qz, qw).normalized()
		obj.global_position = Vector3(px, py, pz)
		obj.global_transform.basis = Basis(q)
		obj.linear_velocity  = Vector3(lvx, lvy, lvz)
		obj.angular_velocity = Vector3(avx, avy, avz)


# ─────────────────────────────────────────────────────────────────────────────
# Freeze / unfreeze
# ─────────────────────────────────────────────────────────────────────────────

func _freeze_objects() -> void:
	for obj in _objects:
		var rb := obj as RigidBody3D
		if is_instance_valid(rb):
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true


func _unfreeze_objects() -> void:
	for obj in _objects:
		var rb := obj as RigidBody3D
		if is_instance_valid(rb):
			rb.freeze = false


## After one Jolt frame, push a fresh context frame from actual physics state
## so the ring buffer stays grounded in real physics at every 4th tick.
func _resync_from_jolt() -> void:
	var ctx_frame : PackedFloat32Array = _build_context_frame()
	_push_ring_frame(ctx_frame)


# ─────────────────────────────────────────────────────────────────────────────
# Normalization stats loader
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Normalization stats loader
# ─────────────────────────────────────────────────────────────────────────────

func _load_norm_stats(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("SonataIIRuntime: normstats not found: " + path)
		return false

	var f    := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("SonataIIRuntime: JSON parse error in: " + path)
		f.close()
		return false
	f.close()

	var d : Dictionary = json.get_data()
	print("[SonataIIRuntime] normstats keys: ", d.keys())  # remove after confirming

	var ss_block  : Dictionary = _get_key(d, ["scene_static",  "scenestatic",  "ss"])
	var os_block  : Dictionary = _get_key(d, ["obj_static",    "objstatic",    "os"])
	var dyn_block : Dictionary = _get_key(d, ["obj_dynamic",   "objdynamic",   "dyn", "dynamic"])
	var nbr_block : Dictionary = _get_key(d, ["neighbourhood", "neighborhood", "nbr", "pairwise"])
	var tgt_block : Dictionary = _get_key(d, ["target",        "tgt"])

	if ss_block.is_empty() or os_block.is_empty() or dyn_block.is_empty() \
	or nbr_block.is_empty() or tgt_block.is_empty():
		push_error("SonataIIRuntime: one or more required blocks missing. Keys found: " + str(d.keys()))
		return false

	_nss_mean  = _to_pfa(ss_block["mean"])
	_nss_std   = _to_pfa(ss_block["std"])
	_nos_mean  = _to_pfa(os_block["mean"])
	_nos_std   = _to_pfa(os_block["std"])
	_ndyn_mean = _to_pfa(dyn_block["mean"])
	_ndyn_std  = _to_pfa(dyn_block["std"])
	_nnbr_mean = _to_pfa(nbr_block["mean"])
	_nnbr_std  = _to_pfa(nbr_block["std"])
	_ntgt_mean = _to_pfa(tgt_block["mean"])
	_ntgt_std  = _to_pfa(tgt_block["std"])

	# Sanity checks
	assert(_nss_mean.size()  == NSCENE,  "scene_static mean size mismatch — got %d expected %d" % [_nss_mean.size(),  NSCENE])
	assert(_nos_mean.size()  == NSTATIC, "obj_static mean size mismatch — got %d expected %d"   % [_nos_mean.size(),  NSTATIC])
	assert(_ndyn_mean.size() == NDYN,    "obj_dynamic mean size mismatch — got %d expected %d"  % [_ndyn_mean.size(), NDYN])
	assert(_nnbr_mean.size() == NNBR,    "neighbourhood mean size mismatch — got %d expected %d"% [_nnbr_mean.size(), NNBR])
	assert(_ntgt_mean.size() == NTARGET, "target mean size mismatch — got %d expected %d"       % [_ntgt_mean.size(), NTARGET])

	print("[SonataIIRuntime] normstats loaded OK — ss:%d os:%d dyn:%d nbr:%d tgt:%d" % [
		_nss_mean.size(), _nos_mean.size(), _ndyn_mean.size(),
		_nnbr_mean.size(), _ntgt_mean.size()
	])
	return true


## Try multiple candidate key names, return the first one found.
## Prints a clear error with all available keys if nothing matches.
func _get_key(d: Dictionary, candidates: Array) -> Dictionary:
	for k in candidates:
		if d.has(k):
			return d[k]
	push_error("SonataIIRuntime: none of these keys found: " + str(candidates))
	push_error("SonataIIRuntime: available keys are:       " + str(d.keys()))
	return {}


func _to_pfa(arr: Array) -> PackedFloat32Array:
	var pfa : PackedFloat32Array
	pfa.resize(arr.size())
	for i in range(arr.size()):
		pfa[i] = float(arr[i])
	return pfa
