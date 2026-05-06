# Scenes/Environment/MLSceneManager.gd
# Attached to a Node3D child of Environment root.
# Listens to SignalManager.object_added — auto-creates the correct
# Runtime (SonataI for solo, SonataII for clusters) for every spawned object.
# Drives all runtimes from _physics_process every tick.

extends Node3D

# ── Runtime pools ──────────────────────────────────────────────────────────────
var _s1_runtimes : Array = []   # Array[SonataIRuntime]
var _s2_runtimes : Array = []   # Array[SonataIIRuntime]

# ── Cluster state ──────────────────────────────────────────────────────────────
# All ground-regime RigidBody3D objects currently live in the scene.
# Re-clustered every time a new object is added.
var _all_bodies  : Array = []   # Array[RigidBody3D]

# ── ML toggle (wired to UI CheckButton — see Step 3) ─────────────────────────
var ml_enabled   : bool  = false

# ── Gravity (read from PhysicsServer3D — valid after _ready) ──────────────────
var _gravity     : Vector3 = Vector3(0.0, -9.8, 0.0)

# ── Norm stat paths ───────────────────────────────────────────────────────────
const _STATS_S1 := "res://ML/NormStats/normstats_sonata1.json"
const _STATS_S2 := "res://ML/NormStats/normstats_sonata2.json"

# ── Cluster XZ radius (must match training) ───────────────────────────────────
const CLUSTER_RADIUS : float = 3.0
const NMAX           : int   = 6

func _ready() -> void:
	# Must always process — not paused by playback button
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Read gravity from project physics settings
	_gravity = PhysicsServer3D.area_get_param(
		get_viewport().find_world_3d().space,
		PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR
	) * PhysicsServer3D.area_get_param(
		get_viewport().find_world_3d().space,
		PhysicsServer3D.AREA_PARAM_GRAVITY
	)

	# Connect to SignalManager — fired by ui.gd on every spawn
	SignalManager.object_added.connect(_on_object_added)
	print("[MLSceneManager] Ready. ML is OFF by default — toggle via UI.")

# ── Called by SignalManager every time ui.gd spawns an object ─────────────────
func _on_object_added(obj: Node3D) -> void:
	if not obj is RigidBody3D:
		return   # ragdolls and floors are not handled here
	var body := obj as RigidBody3D
	if not body.is_in_group("obj"):
		return   # only objects spawned by spawn_button go to ML

	_all_bodies.append(body)
	_rebuild_runtimes()

# ── Rebuild all runtimes from scratch whenever topology changes ────────────────
func _rebuild_runtimes() -> void:
	# Clear old runtimes
	_s1_runtimes.clear()
	_s2_runtimes.clear()

	# Prune freed bodies
	_all_bodies = _all_bodies.filter(func(b): return is_instance_valid(b))

	# Form clusters using 2D XZ greedy algorithm
	var clusters : Array = _cluster_bodies_xz(_all_bodies)

	for cluster in clusters:
		if cluster.size() == 1:
			# Solo object → Sonata-I
			var rt := SonataIRuntime.new()
			var ok : bool = rt.initialize(MLManager, cluster[0], _STATS_S1)
			if ok:
				_s1_runtimes.append(rt)
			else:
				push_error("[MLSceneManager] SonataIRuntime init failed for %s" % cluster[0].name)
		else:
			# Multi-object cluster → Sonata-II
			var rt := SonataIIRuntime.new()
			var ok : bool = rt.initialize(MLManager, cluster, _gravity, _STATS_S2)
			if ok:
				_s2_runtimes.append(rt)
			else:
				push_error("[MLSceneManager] SonataIIRuntime init failed for cluster size %d" % cluster.size())

	print("[MLSceneManager] Rebuilt: %d S1 runtimes, %d S2 runtimes from %d objects" % [
		_s1_runtimes.size(), _s2_runtimes.size(), _all_bodies.size()
	])

# ── Physics tick ───────────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not ml_enabled:
		return

	for rt in _s1_runtimes:
		var r := rt as SonataIRuntime
		if r: r.step()

	for rt in _s2_runtimes:
		var r := rt as SonataIIRuntime
		if r: r.step()

# ── 2D XZ greedy clustering ────────────────────────────────────────────────────
func _cluster_bodies_xz(bodies: Array) -> Array:
	var clusters : Array = []
	var assigned : Dictionary = {}

	for body in bodies:
		if assigned.has(body): continue
		var cluster : Array = [body]
		assigned[body] = true

		for other in bodies:
			if assigned.has(other): continue
			if cluster.size() >= NMAX: break
			var b_pos : Vector3 = body.global_position
			var o_pos : Vector3 = other.global_position
			var xz_dist : float = Vector2(
				b_pos.x - o_pos.x,
				b_pos.z - o_pos.z
			).length()
			if xz_dist <= CLUSTER_RADIUS:
				cluster.append(other)
				assigned[other] = true

		clusters.append(cluster)
	return clusters

# ── Public: called by UI ML toggle button ─────────────────────────────────────
func set_ml_enabled(enabled: bool) -> void:
	ml_enabled = enabled
	print("[MLSceneManager] ML inference: %s" % ("ON" if enabled else "OFF"))
	if not enabled:
		# Unfreeze all bodies so Jolt resumes full control
		for body in _all_bodies:
			if is_instance_valid(body):
				(body as RigidBody3D).freeze = false
