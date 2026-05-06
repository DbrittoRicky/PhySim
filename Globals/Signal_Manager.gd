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

signal spawn_button_pressed(object: PackedScene)
signal object_added(obj: Node3D)
signal object_selected(obj: Node)
signal object_deselected()
signal camera_obj_selected(obj: Node)
signal ragdoll_button_pressed(ragdoll: PackedScene)
signal ragdoll_selected(ragdoll: Node)
signal env_state_changed(state: EnvironmentManager.EnvState)
signal fluid_spawned(fluidArea: FluidVolume3D)


# when the object button is pressed
func on_spawn_button_pressed(object: PackedScene):
	spawn_button_pressed.emit(object)
	
# when an object is added to the environment
func on_object_added(obj: Node3D):
	object_added.emit(obj)

# object selected through outliner
func on_object_selected(obj: Node):
	object_selected.emit(obj)

# object selected through camera
func on_camera_obj_selected(obj_idx: int):
	camera_obj_selected.emit(obj_idx)

# to spawn ragdolls
func on_ragdoll_button_pressed(ragdoll: PackedScene):
	ragdoll_button_pressed.emit(ragdoll)

# ragdoll selected through outliner
func on_ragdoll_selected(ragdoll: Node):
	ragdoll_selected.emit(ragdoll)

# when environment state is changed
func on_env_state_changed(state: EnvironmentManager.EnvState):
	env_state_changed.emit(state)

func on_fluid_spawned(fluidArea: FluidVolume3D):
	fluid_spawned.emit(fluidArea)
	
func on_object_deselected():
	object_deselected.emit()
