extends MarginContainer

func _on_option_button_item_selected(index: int) -> void:
	SignalManager.on_env_state_changed(index)
