extends Camera3D

var orbit_sensitivity := 0.005
var pan_sensitivity := 0.01
var zoom_sensitivity := 1.0

var pitch := 0.0
var yaw := 0.0
var distance := 10.0
var target_position := Vector3.ZERO  # The point to orbit around

func _ready():
	pitch = deg_to_rad(20)  # tilt down a bit
	distance = 10
	target_position = Vector3.ZERO
	_update_camera_position()

func _unhandled_input(event):
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

func _orbit(relative: Vector2):
	yaw -= relative.x * orbit_sensitivity
	pitch += relative.y * orbit_sensitivity
	pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
	_update_camera_position()

func _pan(relative: Vector2):
	# Calculate the right and up directions
	var right = global_transform.basis.x.normalized()
	var up = global_transform.basis.y.normalized()
	
	# Pan in screen space (left/right and up/down)
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
