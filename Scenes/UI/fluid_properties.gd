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
