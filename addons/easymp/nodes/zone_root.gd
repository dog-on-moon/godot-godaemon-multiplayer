extends SubViewportContainer
class_name ZoneRoot
## The root node containing Zones in a ClientNode/ServerNode.

## Settings for propagating input events through the ZoneRoot.
enum PropagatedInputs {
	NONE = 0,        ## No input events will be propagated to zones.
	MOUSE_ONLY = 1,  ## Only mouse events will be propagated to zones.
	ALL = 2,         ## All input events will be propagated to zones.
}

## Determines how input events are propagated through the ZoneRoot.
@export var propagated_inputs := PropagatedInputs.NONE

## A reference to the ClientNode, if it exists.
var client_node: ClientNode

## A reference to the ServerNode, if it exists.
var server_node: ServerNode

func _ready() -> void:
	name = 'ZoneRoot'
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true

func _enter_tree() -> void:
	client_node = get_parent() if get_parent() is ClientNode else null
	server_node = get_parent() if get_parent() is ServerNode else null

func _exit_tree() -> void:
	client_node = null
	server_node = null

func _propagate_input_event(event: InputEvent) -> bool:
	match propagated_inputs:
		PropagatedInputs.NONE:
			return false
		PropagatedInputs.MOUSE_ONLY:
			return event is InputEventMouse
		PropagatedInputs.ALL:
			return true
	return false
