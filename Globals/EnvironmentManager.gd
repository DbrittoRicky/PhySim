#Physics Simulation Environment - A Godot 4 physics sandbox with ragdolls,
#fluid dynamics, and a Blender-like editor interface.
#Copyright (C) 2026 Tricia Almeida
#Copyright (C) 2026 Ricky Dbritto
#Copyright (C) 2026 Steve Miranda
#Copyright (C) 2026 Dhruv Dalvi
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
