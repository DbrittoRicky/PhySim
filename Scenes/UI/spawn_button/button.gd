extends Button

@export var object: PackedScene

func _ready() -> void:
	text = str(object.resource_path.get_file().get_basename())


func _on_pressed() -> void:
	SignalManager.on_spawn_button_pressed(object)
	focus_mode = 0
