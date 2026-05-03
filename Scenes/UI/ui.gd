extends Control

#Probably the messiest script in the project for now

@onready var add_floor: Window = $"Top Panel/HBoxContainer/VBOx/Add Floor"
@onready var item_list: ItemList = $Outliner/VBoxContainer/Objects/ItemList
@onready var playback_button: Button = $Playback/HBoxContainer/Playback_button
@onready var add_fluid: Window = $"Top Panel/HBoxContainer/VBOx/Add Fluid"

# ── ML Toggle ─────────────────────────────────────────────────────────────────
# Wire this @onready ONLY after you add the CheckButton node in the editor.
# Path mirrors the exact location of Add Floor and Add Fluid in the scene tree.
@onready var ml_toggle: CheckButton = $"Top Panel/HBoxContainer/VBOx/MLToggle"

var name_counters := {}

func _ready() -> void:
	SignalManager.spawn_button_pressed.connect(spawn_button_pressed)
	SignalManager.ragdoll_button_pressed.connect(ragdoll_button_pressed)


func ragdoll_button_pressed(ragdoll: PackedScene) -> void:
	var new_ragdoll = ragdoll.instantiate()
	new_ragdoll.add_to_group("Ragdoll")
	var base_name = new_ragdoll.name
	var unique_name = _get_unique_name(base_name)
	new_ragdoll.name = unique_name
	SignalManager.on_object_added(new_ragdoll)
	new_ragdoll.global_position = Vector3(0,0,0)
	add_child(new_ragdoll)


func spawn_button_pressed(object: PackedScene) -> void:
	var new_obj = object.instantiate()
	new_obj.add_to_group('obj')
	var phys_mat = PhysicsMaterial.new()
	new_obj.physics_material_override = phys_mat
	var base_name = new_obj.name
	var unique_name = _get_unique_name(base_name)
	new_obj.name = unique_name
	
	SignalManager.on_object_added(new_obj)
	new_obj.global_position = Vector3(0, 5, 0)
	add_child(new_obj)


# This should be in outliner.gd
# check if an instance of object already exists
func _name_exists(name: String) -> bool:
	for i in range(item_list.item_count):
		if item_list.get_item_text(i) == name:
			return true
	return false

func _get_unique_name(base_name: String) -> String:
	# If it's the first time we see this name
	if not name_counters.has(base_name):
		name_counters[base_name] = 0

	var candidate = base_name
	if _name_exists(candidate):
		name_counters[base_name] += 1
		candidate = "%s-%d" % [base_name, name_counters[base_name]]

	return candidate

func _on_add_floor_pressed() -> void:
	add_floor.visible = true


func _on_button_pressed() -> void:
	add_fluid.visible = true


# ── ML Toggle handler ─────────────────────────────────────────────────────────
# Connected via the Godot editor: MLToggle node → toggled(button_pressed) signal
# Do NOT connect this manually in _ready() — use the editor Signals tab.
func _on_ml_toggle_toggled(button_pressed: bool) -> void:
	ml_toggle.text = "ML On" if button_pressed else "ML Off"

	# Locate MLSceneManager by group — avoids any hardcoded scene tree path.
	# MLSceneManager node must be added to group "ml_scene_manager" in the editor.
	var managers := get_tree().get_nodes_in_group("ml_scene_manager")
	if managers.is_empty():
		push_error("[ui.gd] MLSceneManager not found in group 'ml_scene_manager'. " +
				   "Did you add the node to that group in environment.tscn?")
		return

	(managers[0] as Node).call("set_ml_enabled", button_pressed)
