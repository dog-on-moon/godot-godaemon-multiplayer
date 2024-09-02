extends SubViewportContainer
class_name ZoneService
## The root node containing Zones in a ClientNode/ServerNode.

#region Inputs

## Settings for propagating input events through the ZoneService.
enum PropagatedInputs {
	NONE = 0,        ## No input events will be propagated to zones.
	MOUSE_ONLY = 1,  ## Only mouse events will be propagated to zones.
	ALL = 2,         ## All input events will be propagated to zones.
}

## Determines how input events are propagated through the ZoneService.
@export var propagated_inputs := PropagatedInputs.NONE

func _propagate_input_event(event: InputEvent) -> bool:
	match propagated_inputs:
		PropagatedInputs.NONE:
			return false
		PropagatedInputs.MOUSE_ONLY:
			return event is InputEventMouse
		PropagatedInputs.ALL:
			return true
	return false

#endregion

@onready var mp := MultiplayerNode.fetch(self)

func _ready() -> void:
	name = 'ZoneService'
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
