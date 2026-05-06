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

@onready var metrics_label: Label = $metrics_label

var fps: float
var physics_time: float
var idle_time: float
var vram: float
var object_count: int
var static_mem: float

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	fps = Engine.get_frames_per_second()
	physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	idle_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	vram = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	static_mem = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	
	update_metrics()
	

func update_metrics() -> void:
	metrics_label.text = """
	FPS: %.2f
	Physics Time: %.2f ms
	Idle Time: %.2f ms
	VRAM: %.2f MB
	Memory: %.2f MB
	""" % [fps, physics_time, idle_time, vram, static_mem]
