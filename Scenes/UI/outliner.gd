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

extends MarginContainer

@onready var item_list: ItemList = $VBoxContainer/Objects/ItemList
@onready var physics_properties: VBoxContainer = $"VBoxContainer/Physics Properties"
@onready var ragdoll_properties: Ragdoll_Property = $"VBoxContainer/Ragdoll properties"

func _ready() -> void:
	SignalManager.object_added.connect(register_obj)
	SignalManager.object_selected.connect(on_item_selected)
	SignalManager.ragdoll_selected.connect(on_ragdoll_selected)
	physics_properties.visible = false

# add the object to item_list
func register_obj(obj: Node3D):
	var name = obj.name
	if obj.is_in_group('obj') or obj.is_in_group("Ragdoll"):
		item_list.add_item(name)


# In your outliner script
func on_item_selected(obj:Node):
	physics_properties.set_selected_object(obj)
	physics_properties.visible = true
	if ragdoll_properties.visible == true:
		ragdoll_properties.visible = false
	
func on_ragdoll_selected(ragdoll: Ragdoll):
	ragdoll_properties.set_selected_ragdoll(ragdoll)
	ragdoll_properties.visible = true
	if physics_properties.visible == true:
		physics_properties.visible = false


#func add_to_itemlist() -> void:
	#for i in get_tree().get_nodes_in_group("obj"):
		#register_obj(i)

	
