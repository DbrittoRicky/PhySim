extends Node

@export var vaccum_damp_mult := 0.0
@export var atomos_damp_mult := 1.0

enum EnvState {VACCUM, ATMOSPHERE}

var current_state: EnvState = EnvState.VACCUM

var air_drag := 0.15

func _ready() -> void:
	SignalManager.env_state_changed.connect(set_state)

func set_state(new_state: EnvState) -> void:
	current_state = new_state

func get_drag_coefficeint() -> float:
	match current_state:
		EnvState.VACCUM:
			return 0.0
		EnvState.ATMOSPHERE:
			return air_drag
	return 0.0
