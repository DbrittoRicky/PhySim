extends Node3D

var mouse_position: Vector2


func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	mouse_position = get_viewport().get_mouse_position()
