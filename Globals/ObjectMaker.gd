# Globals/ObjectMaker.gd
# Autoloaded singleton. Handles all runtime object spawning for PhySim.
# Emits SignalManager.object_added after every spawn so the scene and
# ML runtimes can react. Stores per-object static metadata as Node3D meta
# so SonataIRuntime / SonataIIRuntime can read it without scene coupling.

extends Node

# ── Shape type enum (must match your training data encoding) ───────────────────
enum ShapeType { BOX = 0, SPHERE = 1, CAPSULE = 2, CYLINDER = 3 }

# ── Physics material defaults ──────────────────────────────────────────────────
const DEFAULT_FRICTION  : float = 0.5
const DEFAULT_BOUNCE    : float = 0.0
const DEFAULT_L_DAMP    : float = 0.0
const DEFAULT_A_DAMP    : float = 0.0
const DEFAULT_MASS      : float = 1.0
const DEFAULT_GRAV_SCALE: float = 1.0

# ── Internal tracking ──────────────────────────────────────────────────────────
var _spawned_objects : Array = []   # Array[RigidBody3D] — all live objects

# ── Public API ─────────────────────────────────────────────────────────────────

## Spawn a primitive rigid body at world_pos.
## shape_type: ShapeType enum value
## size: Vector3 — for BOX: half-extents, SPHERE: x=radius, CAPSULE: x=radius y=height
## Returns the spawned RigidBody3D or null on failure.
func spawn_object(
	shape_type  : int,
	size        : Vector3,
	world_pos   : Vector3,
	mass        : float = DEFAULT_MASS,
	friction    : float = DEFAULT_FRICTION,
	bounce      : float = DEFAULT_BOUNCE,
	grav_scale  : float = DEFAULT_GRAV_SCALE,
	linear_damp : float = DEFAULT_L_DAMP,
	angular_damp: float = DEFAULT_A_DAMP
) -> RigidBody3D:

	var body := RigidBody3D.new()
	body.mass          = mass
	body.gravity_scale = grav_scale
	body.linear_damp   = linear_damp
	body.angular_damp  = angular_damp

	# Physics material
	var mat := PhysicsMaterial.new()
	mat.friction = friction
	mat.bounce   = bounce
	body.physics_material_override = mat

	# Collision shape
	var col   := CollisionShape3D.new()
	var shape : Shape3D
	var dim_primary   : float = 0.0
	var dim_secondary : float = 0.0

	match shape_type:
		ShapeType.BOX:
			var s    := BoxShape3D.new()
			s.size    = size * 2.0   # size is half-extents; BoxShape3D takes full size
			shape     = s
			dim_primary   = size.x
			dim_secondary = size.y

		ShapeType.SPHERE:
			var s    := SphereShape3D.new()
			s.radius  = size.x
			shape     = s
			dim_primary   = size.x
			dim_secondary = 0.0

		ShapeType.CAPSULE:
			var s    := CapsuleShape3D.new()
			s.radius  = size.x
			s.height  = size.y
			shape     = s
			dim_primary   = size.x
			dim_secondary = size.y

		ShapeType.CYLINDER:
			var s    := CylinderShape3D.new()
			s.radius  = size.x
			s.height  = size.y
			shape     = s
			dim_primary   = size.x
			dim_secondary = size.y

		_:
			push_error("ObjectMaker: unknown shape_type %d" % shape_type)
			return null

	col.shape = shape
	body.add_child(col)

	# Visual mesh (MeshInstance3D mirrors the collision shape)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _make_mesh(shape_type, size)
	body.add_child(mesh_inst)

	# ── ML metadata (read by SonataIRuntime / SonataIIRuntime) ────────────────
	body.set_meta("shape_type_int",  shape_type)
	body.set_meta("dim_primary",     dim_primary)
	body.set_meta("dim_secondary",   dim_secondary)
	# env_state_binary is set dynamically when fluid state changes (see below)
	body.set_meta("env_state_binary", 0)

	# ── Apply environment damping from EnvironmentManager ─────────────────────
	_apply_env_damping(body)

	# ── Place in world ────────────────────────────────────────────────────────
	body.global_position = world_pos
	_spawned_objects.append(body)

	# ── Signal bus ────────────────────────────────────────────────────────────
	SignalManager.on_object_added(body)

	return body

## Spawn from a PackedScene (called when UI spawn button is pressed).
## The scene root must be a RigidBody3D with metadata already set,
## OR ObjectMaker will attempt to read shape from its first CollisionShape3D child.
func spawn_from_scene(packed: PackedScene, world_pos: Vector3) -> Node3D:
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("ObjectMaker: packed scene root is not Node3D")
		return null

	instance.global_position = world_pos
	_spawned_objects.append(instance)

	# Infer and set metadata if not already present
	if instance is RigidBody3D:
		_infer_and_set_meta(instance as RigidBody3D)
		_apply_env_damping(instance as RigidBody3D)

	SignalManager.on_object_added(instance)
	return instance

## Remove a single object from the world and tracking list.
func remove_object(obj: Node3D) -> void:
	_spawned_objects.erase(obj)
	if is_instance_valid(obj):
		obj.queue_free()

## Remove all spawned objects.
func clear_all() -> void:
	for obj in _spawned_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	_spawned_objects.clear()

## Returns all currently live RigidBody3D objects.
func get_all_bodies() -> Array:
	# Prune any freed instances first
	_spawned_objects = _spawned_objects.filter(func(o): return is_instance_valid(o))
	return _spawned_objects.duplicate()

## Update env_state_binary metadata on all objects when fluid state changes.
## Connected to SignalManager.env_state_changed in _ready().
func on_env_state_changed(state: EnvironmentManager.EnvState) -> void:
	var binary : int = 1 if state == EnvironmentManager.EnvState.ATMOSPHERE else 0
	for obj in _spawned_objects:
		if is_instance_valid(obj):
			obj.set_meta("env_state_binary", binary)
	_update_all_damping(state)

# ── Internal helpers ───────────────────────────────────────────────────────────

func _ready() -> void:
	SignalManager.env_state_changed.connect(on_env_state_changed)
	SignalManager.spawn_button_pressed.connect(_on_spawn_button_pressed)

func _on_spawn_button_pressed(packed: PackedScene) -> void:
	# Default spawn position: slightly above world origin
	# The UI / camera system should override this with a raycast hit position.
	spawn_from_scene(packed, Vector3(0.0, 2.0, 0.0))

func _apply_env_damping(body: RigidBody3D) -> void:
	var drag : float = EnvironmentManager.get_drag_coefficeint()
	body.linear_damp  = maxf(body.linear_damp,  drag)
	body.angular_damp = maxf(body.angular_damp, drag * 0.5)

func _update_all_damping(state: EnvironmentManager.EnvState) -> void:
	var drag : float = EnvironmentManager.get_drag_coefficeint()
	for obj in _spawned_objects:
		if is_instance_valid(obj) and obj is RigidBody3D:
			var rb := obj as RigidBody3D
			rb.linear_damp  = drag
			rb.angular_damp = drag * 0.5

func _infer_and_set_meta(body: RigidBody3D) -> void:
	# If a packed scene didn't set metadata, infer it from the first CollisionShape3D
	if body.has_meta("shape_type_int"): return
	for child in body.get_children():
		if child is CollisionShape3D:
			var col := child as CollisionShape3D
			if col.shape is BoxShape3D:
				var s := col.shape as BoxShape3D
				body.set_meta("shape_type_int",  ShapeType.BOX)
				body.set_meta("dim_primary",     s.size.x * 0.5)
				body.set_meta("dim_secondary",   s.size.y * 0.5)
			elif col.shape is SphereShape3D:
				var s := col.shape as SphereShape3D
				body.set_meta("shape_type_int",  ShapeType.SPHERE)
				body.set_meta("dim_primary",     s.radius)
				body.set_meta("dim_secondary",   0.0)
			elif col.shape is CapsuleShape3D:
				var s := col.shape as CapsuleShape3D
				body.set_meta("shape_type_int",  ShapeType.CAPSULE)
				body.set_meta("dim_primary",     s.radius)
				body.set_meta("dim_secondary",   s.height)
			elif col.shape is CylinderShape3D:
				var s := col.shape as CylinderShape3D
				body.set_meta("shape_type_int",  ShapeType.CYLINDER)
				body.set_meta("dim_primary",     s.radius)
				body.set_meta("dim_secondary",   s.height)
			else:
				body.set_meta("shape_type_int",  0)
				body.set_meta("dim_primary",     0.0)
				body.set_meta("dim_secondary",   0.0)
			body.set_meta("env_state_binary", 0)
			return
	# No CollisionShape3D found — set safe defaults
	body.set_meta("shape_type_int",  0)
	body.set_meta("dim_primary",     0.0)
	body.set_meta("dim_secondary",   0.0)
	body.set_meta("env_state_binary", 0)

func _make_mesh(shape_type: int, size: Vector3) -> Mesh:
	match shape_type:
		ShapeType.BOX:
			var m := BoxMesh.new()
			m.size = size * 2.0
			return m
		ShapeType.SPHERE:
			var m := SphereMesh.new()
			m.radius = size.x
			m.height = size.x * 2.0
			return m
		ShapeType.CAPSULE:
			var m := CapsuleMesh.new()
			m.radius = size.x
			m.height = size.y
			return m
		ShapeType.CYLINDER:
			var m := CylinderMesh.new()
			m.top_radius    = size.x
			m.bottom_radius = size.x
			m.height        = size.y
			return m
	return BoxMesh.new()   # safe fallback
