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

extends ItemList

func _on_item_selected(index: int) -> void:
	var obj_list = get_tree().get_nodes_in_group("obj")
	var obj = obj_list[index]
	if obj is not Ragdoll:
		SignalManager.on_object_selected(obj)
	if obj is Ragdoll:
		SignalManager.on_ragdoll_selected(obj)

func _ready() -> void:
	SignalManager.camera_obj_selected.connect(select)
