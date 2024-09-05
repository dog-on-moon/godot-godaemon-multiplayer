extends SubViewportContainer
## Sets up the SubViewportContainer for the ZoneService.

## Settings for propagating input events through the ZoneService.
enum PropagatedInputs {
	NONE = 0,        ## No input events will be propagated to zones.
	MOUSE_ONLY = 1,  ## Only mouse events will be propagated to zones.
	ALL = 2,         ## All input events will be propagated to zones.
}

## Determines how input events are propagated through the ZoneService.
@export var propagated_inputs := PropagatedInputs.ALL

func _propagate_input_event(event: InputEvent) -> bool:
	match propagated_inputs:
		PropagatedInputs.NONE:
			return false
		PropagatedInputs.MOUSE_ONLY:
			return event is InputEventMouse
		PropagatedInputs.ALL:
			return true
	return false

@onready var mp := MultiplayerRoot.fetch(self)

func _ready() -> void:
	# Setup viewport container visuals.
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	visible = true
	propagated_inputs = PropagatedInputs.ALL
	if mp.is_server() and get_viewport() == get_window():
		visible = false
		propagated_inputs = PropagatedInputs.NONE
