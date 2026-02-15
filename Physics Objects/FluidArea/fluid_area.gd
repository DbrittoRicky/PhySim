extends Area3D
class_name FluidVolume3D

@export var fluid_density: float = 1000.0  # kg/m³ (water = 1000, oil ~900, air ~1.2)
@export var fluid_drag_multiplier: float = 50.0  # fluids have much higher drag than air


var _submerged_bodies: Array[RigidBody3D] = []

func _ready() -> void:
	monitoring = true  # enable detection [page:6]
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

	for body in _submerged_bodies:
		if not is_instance_valid(body):
			continue
		
		_apply_buoyancy(body, gravity)
		_apply_fluid_drag(body)



func get_submerged_bodies() -> Array[RigidBody3D]:
	return _submerged_bodies

# ----------------------------
# Buoyancy
# ----------------------------

func _apply_buoyancy(body: Phy_Obj, gravity: float) -> void:
	if body.volume <= 0:
		return
	var collision_shape := get_child(0)
	if collision_shape == null:
		return
	
	var shape = collision_shape.shape
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		var half_height := box.size.y * 0.5
		
		# Top surface of water
		var surface_y := global_position.y + half_height
		
		# Object dimensions
		var body_height = body.get_body_height_y()
		var body_half_height = body_height * 0.5
		
		# Bottom of object (NOT center)
		var object_bottom_y = body.global_position.y - body_half_height
		var object_top_y = body.global_position.y + body_half_height
		
		# How much is underwater
		var submerged_height = clamp(surface_y - object_bottom_y, 0.0, body_height)
		var submerged_ratio = submerged_height / body_height
		
		# Apply buoyancy force
		var displaced_volume = body.volume * submerged_ratio
		var buoyant_force = fluid_density * gravity * displaced_volume
		
		body.apply_central_force(Vector3.UP * buoyant_force)


# ----------------------------
# Fluid Drag
# ----------------------------

func _apply_fluid_drag(body: Phy_Obj) -> void:
	var velocity := body.linear_velocity
	
	var drag_force := -velocity * fluid_drag_multiplier
	
	body.apply_central_force(drag_force)


func _on_body_entered(body: Node3D) -> void:
	if body is Phy_Obj and not _submerged_bodies.has(body):
		_submerged_bodies.append(body)
		body.is_in_fluid = true


func _on_body_exited(body: Node3D) -> void:
	if body is Phy_Obj:
		_submerged_bodies.erase(body)
		body.is_in_fluid = false
