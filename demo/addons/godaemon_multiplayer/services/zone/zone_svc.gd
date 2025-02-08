extends SubViewportContainer
## Sets up the SubViewportContainer for the ZoneService.

func _ready() -> void:
	# Setup viewport container visuals.
	position = Vector2.ZERO
	size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	set_process_shortcut_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	visible = false
