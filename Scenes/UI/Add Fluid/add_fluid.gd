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

extends Window

@onready var x_dim: LineEdit = $VBoxContainer/HBoxContainer/X_dim
@onready var y_dim: LineEdit = $VBoxContainer/HBoxContainer2/Y_dim
@onready var z_dim: LineEdit = $VBoxContainer/HBoxContainer3/Z_dim
@onready var button: Button = $VBoxContainer/Button

func _on_button_pressed() -> void:
	var x = x_dim.text.to_float()
	var y = y_dim.text.to_float()
	var z = z_dim.text.to_float()
	
	if x <= 0.0 or y <= 0.0 or z <= 0.0:
		push_warning("Invalid dimensions") 
	
	create_fluid_volume(x,y,z)
	visible = false

func create_fluid_volume(x: float, y: float, z: float) -> void:
	var new_fluid = FluidVolume3D.new()
	var mesh_instance = MeshInstance3D.new()
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	var box_mesh = BoxMesh.new()
	var mat = StandardMaterial3D.new()
	
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.5, 0.8, 0.3)
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
	box_mesh.size = Vector3(x,y,z)
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = mat
	box_shape.size = Vector3(x,y,z)
	collision_shape.shape = box_shape
	new_fluid.add_child(collision_shape)
	new_fluid.add_child(mesh_instance)
	new_fluid.global_position = Vector3(0,y/2.0,0)
	get_tree().current_scene.add_child(new_fluid)
	SignalManager.on_fluid_spawned(new_fluid)
	
func _on_close_requested() -> void:
	visible = false
