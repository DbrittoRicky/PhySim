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

@onready var button: Button = $VBoxContainer/Button
@onready var x_dim: LineEdit = $"VBoxContainer/HBoxContainer/X-dim"
@onready var z_dim: LineEdit = $"VBoxContainer/HBoxContainer2/Z-dim"


func _on_button_pressed() -> void:
	var x_size = x_dim.text.to_float()
	var z_size = z_dim.text.to_float()
	
	if x_size <=0 or z_size <=0:
		push_warning("Invalid size!")
		return
	
	create_floor(x_size,z_size)
	
	visible = false

func create_floor(x: float, z: float):
	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	var mesh_material = StandardMaterial3D.new()
	mesh_material.albedo_color = Color.SLATE_GRAY
	plane_mesh.size = Vector2(x,z)
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = mesh_material
	mesh_instance.global_position = Vector3(0, 0, 0)
	add_child(mesh_instance)
	
	var collision = StaticBody3D.new()
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(x, 0.01, z)
	collider.shape = shape
	collision.add_child(collider)
	mesh_instance.add_child(collision)
	


func _on_close_requested() -> void:
	visible = false
