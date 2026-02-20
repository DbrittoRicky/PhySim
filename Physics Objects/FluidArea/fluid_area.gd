extends Area3D
class_name FluidVolume3D

@export var fluid_density: float = 1000.0

# Fluid resistance (simple)
@export var linear_drag: float = 8.0
@export var angular_drag: float = 4.0

# Buoyancy stabilization
@export var buoyancy_vertical_damp: float = 25.0    # N per (m/s) per kg-ish (tune)
@export var max_buoyant_accel: float = 80.0         # m/s² clamp to prevent “rocket” behavior
@export var waterline_epsilon: float = 0.02         # meters; smooth near surface

var _submerged_bodies: Array[RigidBody3D] = []
var _gravity: float = 0.0

@onready var _fluid_col: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(_delta: float) -> void:
	for i in range(_submerged_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_submerged_bodies[i]):
			_submerged_bodies.remove_at(i)

	for rb in _submerged_bodies:
		var body := rb as Phy_Obj
		if body == null or body.freeze: # ignore frozen bodies (forces do nothing anyway) [page:11]
			continue

		var sub := _get_submersion(body) # {ratio, submerged_height}
		if sub.ratio <= 0.0:
			continue

		_apply_buoyancy_stable(body, sub.submerged_height, sub.ratio)
		_apply_linear_drag(body, sub.ratio)
		_apply_angular_drag(body, sub.ratio)

# Returns continuous submersion for Box fluid volumes.
# For non-box volumes, you can treat as fully submerged to keep it simple.
func _get_submersion(body: Phy_Obj) -> Dictionary:
	if _fluid_col == null or _fluid_col.shape == null:
		return { "ratio": 1.0, "submerged_height": body.get_body_height_y() }

	if not (_fluid_col.shape is BoxShape3D):
		return { "ratio": 1.0, "submerged_height": body.get_body_height_y() }

	var box := _fluid_col.shape as BoxShape3D
	var surface_y := global_position.y + box.size.y * 0.5

	var h = max(body.get_body_height_y(), 0.0001)
	var bottom_y = body.global_position.y - h * 0.5

	var submerged_h = clamp(surface_y - bottom_y, 0.0, h)
	var ratio = submerged_h / h

	# Smooth the first few centimeters to avoid “force snapping” at the waterline
	if submerged_h < waterline_epsilon:
		var t = submerged_h / waterline_epsilon
		ratio *= t * t * (3.0 - 2.0 * t) # smoothstep

	return { "ratio": ratio, "submerged_height": submerged_h }

func _apply_buoyancy_stable(body: Phy_Obj, submerged_h: float, ratio: float) -> void:
	if body.volume <= 0.0:
		return

	# Correct Archimedes buoyancy
	var displaced_volume := body.volume * ratio
	var buoyant_force := fluid_density * _gravity * displaced_volume

	# Velocity damping ONLY when near equilibrium
	var vertical_damp := -body.linear_velocity.y * body.mass * 6.0 * ratio

	var total := buoyant_force + vertical_damp

	# Clamp extreme acceleration
	var max_force := body.mass * max_buoyant_accel
	total = clamp(total, -max_force, max_force)

	body.apply_central_force(Vector3.UP * total)

func _apply_linear_drag(body: Phy_Obj, ratio: float) -> void:
	var vel := body.linear_velocity
	var horizontal := Vector3(vel.x, 0, vel.z)

	body.apply_central_force(-linear_drag * ratio * horizontal)

	# lighter vertical drag (prevents hover bias)
	body.apply_central_force(Vector3(0, -vel.y * 2.0 * ratio, 0))

func _apply_angular_drag(body: Phy_Obj, ratio: float) -> void:
	body.apply_torque(-angular_drag * ratio * body.angular_velocity) # requires collision shapes/inertia [page:11]

func _on_body_entered(body: Node3D) -> void:
	if body is Phy_Obj and not _submerged_bodies.has(body):
		_submerged_bodies.append(body)
		body.is_in_fluid = true

func _on_body_exited(body: Node3D) -> void:
	if body is Phy_Obj:
		_submerged_bodies.erase(body)
		body.is_in_fluid = false
