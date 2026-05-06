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

extends VBoxContainer
class_name Fluid_Properties

@onready var fluid_density: Label = $Fluid_density
@onready var fluid_den_edit: LineEdit = $fluid_den_edit

var fluid : FluidVolume3D

func _ready() -> void:
	SignalManager.fluid_spawned.connect(set_inital_fluid_properties)
	visible = false


func update_value() -> void:
	fluid_density.text = "Fluid density:" + str(fluid.fluid_density)
	
func set_inital_fluid_properties(new_fluid: FluidVolume3D) -> void:
	fluid = new_fluid
	fluid_den_edit.text = str(fluid.fluid_density)
	visible = true


func _on_fluid_den_edit_text_submitted(new_text: String) -> void:
	fluid.fluid_density = float(new_text)
	update_value()
