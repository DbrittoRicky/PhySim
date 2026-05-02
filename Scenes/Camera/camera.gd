extends Camera3D
@onready var ray_cast_3d: RayCast3D = $RayCast3D

var physics_property
var ragdoll_property
var orbit_sensitivity := 0.005
var pan_sensitivity := 0.01
var zoom_sensitivity := 1.0

var pitch := 0.0
var yaw := 0.0
var distance := 10.0
var target_position := Vector3.ZERO

# --- Drag state ---
var dragged_object: Phy_Obj = null
var drag_depth := 0.0
var drag_offset := Vector3.ZERO

# --- Flick/throw velocity tracking ---
const VELOCITY_HISTORY_SIZE := 6
var _pos_history: Array[Vector3] = []
var _time_history: Array[float] = []

# --- Floor/collision safety ---
const FLOOR_Y := 0.0
var _object_half_height := 0.0

# --- Deferred grab: intent detection ---
# We don't commit to a drag until the mouse has moved DRAG_THRESHOLD pixels.
# Until then the press is treated as a potential click.
const DRAG_THRESHOLD := 5.0          # pixels
var _pending_grab_object: Phy_Obj = null  # candidate object on mouse-down
var _press_position := Vector2.ZERO       # screen position of the mouse-down


func _ready():
	physics_property = get_tree().get_first_node_in_group("Physics_property")
	ragdoll_property = get_tree().get_first_node_in_group("Ragdoll Property")
	pitch = deg_to_rad(20)
	distance = 10
	target_position = Vector3.ZERO
	_update_camera_position()


func _process(delta: float) -> void:
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	ray_cast_3d.target_position = project_local_ray_normal(mouse_position) * 100
	ray_cast_3d.force_raycast_update()

	if dragged_object:
		_drag_object(mouse_position)
	# select_object_click() is now driven from _unhandled_input, not _process


# ─── SELECTION ───────────────────────────────────────────────────────────────

func _do_select(collider: Node) -> void:
	# Perform the actual selection logic (previously inside select_object_click)
	var nodes = get_tree().get_nodes_in_group("obj")
	var index = nodes.find(collider)
	if collider is not Ragdoll:
		physics_property.set_selected_object(collider)
		physics_property.visible = true
		SignalManager.on_camera_obj_selected(index)
	elif collider is Ragdoll:
		var parent = collider.get_parent_node_3d()
		var parent_2 = parent.get_parent_node_3d()
		SignalManager.on_camera_obj_selected(parent_2)


# ─── DRAG & DROP ─────────────────────────────────────────────────────────────

func _record_pending_grab() -> void:
	# Called on mouse-down. Store the candidate but do NOT freeze yet.
	if not ray_cast_3d.is_colliding():
		return
	var collider = ray_cast_3d.get_collider()
	if collider is not Phy_Obj or collider is Ragdoll:
		return
	_pending_grab_object = collider as Phy_Obj
	_press_position = get_viewport().get_mouse_position()


func _commit_grab() -> void:
	# Called only once the mouse has moved past DRAG_THRESHOLD.
	# Now we actually freeze the object and start dragging.
	if not _pending_grab_object:
		return

	dragged_object = _pending_grab_object
	_pending_grab_object = null

	drag_depth = global_position.distance_to(dragged_object.global_position)

	var hit_point: Vector3 = ray_cast_3d.get_collision_point()
	# Recompute hit point from current mouse pos since we deferred the grab
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := project_ray_origin(mouse_pos)
	var ray_dir := project_ray_normal(mouse_pos)
	# Project onto a plane at drag_depth to get the world-space grab point
	hit_point = ray_origin + ray_dir * drag_depth
	drag_offset = hit_point - dragged_object.global_position

	_object_half_height = dragged_object.get_body_height_y() * 0.5

	dragged_object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	dragged_object.freeze = true
	dragged_object.linear_velocity = Vector3.ZERO
	dragged_object.angular_velocity = Vector3.ZERO

	_pos_history.clear()
	_time_history.clear()
	for i in VELOCITY_HISTORY_SIZE:
		_pos_history.append(dragged_object.global_position)
		_time_history.append(Time.get_ticks_msec() / 1000.0)


func _drag_object(mouse_pos: Vector2) -> void:
	var ray_origin: Vector3 = project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = project_ray_normal(mouse_pos)
	var world_pos: Vector3 = ray_origin + ray_dir * drag_depth
	var target_pos: Vector3 = world_pos - drag_offset

	var min_y: float = FLOOR_Y + _object_half_height
	target_pos.y = max(target_pos.y, min_y)

	dragged_object.global_position = target_pos

	var now: float = Time.get_ticks_msec() / 1000.0
	_pos_history.append(target_pos)
	_time_history.append(now)
	if _pos_history.size() > VELOCITY_HISTORY_SIZE:
		_pos_history.pop_front()
		_time_history.pop_front()


func _release() -> void:
	# Mouse-up while a committed drag is active → throw the object
	if dragged_object:
		var throw_velocity := Vector3.ZERO
		if _pos_history.size() >= 2:
			var dt: float = _time_history.back() - _time_history.front()
			if dt > 0.001:
				var dp: Vector3 = _pos_history.back() - _pos_history.front()
				throw_velocity = dp / dt

		dragged_object.freeze = false
		dragged_object.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		dragged_object.linear_velocity = throw_velocity

		dragged_object = null
		drag_offset = Vector3.ZERO
		drag_depth = 0.0
		_object_half_height = 0.0
		_pos_history.clear()
		_time_history.clear()

	# Mouse-up while still in pending (threshold never crossed) → treat as click
	elif _pending_grab_object:
		_do_select(_pending_grab_object)
		_pending_grab_object = null
		_press_position = Vector2.ZERO


# ─── INPUT ───────────────────────────────────────────────────────────────────

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_record_pending_grab()
		else:
			_release()
		return

	# Once pending, watch mouse motion to decide: drag or click?
	if event is InputEventMouseMotion and _pending_grab_object:
		var current_pos := get_viewport().get_mouse_position()
		if current_pos.distance_to(_press_position) >= DRAG_THRESHOLD:
			_commit_grab()
		return  # consume motion events while deciding

	# Block camera controls during an active drag
	if dragged_object:
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if Input.is_key_pressed(KEY_SHIFT):
			_pan(event.relative)
		elif not Input.is_key_pressed(KEY_CTRL):
			_orbit(event.relative)

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(-zoom_sensitivity)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(zoom_sensitivity)


# ─── CAMERA CONTROLS ─────────────────────────────────────────────────────────

func _orbit(relative: Vector2):
	yaw -= relative.x * orbit_sensitivity
	pitch += relative.y * orbit_sensitivity
	pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
	_update_camera_position()

func _pan(relative: Vector2):
	var right = global_transform.basis.x.normalized()
	var up = global_transform.basis.y.normalized()
	target_position -= (right * relative.x + up * -relative.y) * pan_sensitivity
	_update_camera_position()

func _zoom(amount: float):
	distance = max(0.1, distance + amount)
	_update_camera_position()

func _update_camera_position():
	var offset = Vector3(
		distance * cos(pitch) * sin(yaw),
		distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	global_position = target_position + offset
	look_at(target_position, Vector3.UP)
