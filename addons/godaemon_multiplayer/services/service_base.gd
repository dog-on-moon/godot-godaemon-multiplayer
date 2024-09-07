@icon("res://addons/godaemon_multiplayer/icons/GDScript.svg")
extends Node
class_name ServiceBase
## Base class for all Service nodes.
##
## A Service can be thought of as a multiplayer autoload.
## It is created underneath a MultiplayerRoot upon a successful connection,
## and removed once the connection is closed.
##
## Services can directly RPC to its corresponding client/server service,
## making them useful for implementing high-level multiplayer functionality.

## A reference to the MultiplayerRoot.
var mp: MultiplayerRoot

## Internal setup function. Called after [method Node._ready].
func _setup():
	if get_reserved_channels() > 0:
		mp.api.rpc.set_node_channel_override(self, get_initial_channel(mp))

## The number of ENet communication channels this Service reserves for itself.
## When non-zero, all RPCs on this Service's node will be set to use the base channel.
## Combined with [method get_initial_channel], you can efficiently route messages with [method send_message].
func get_reserved_channels() -> int:
	return 0

## The initial channel index of our reserved channels.
func get_initial_channel(mp: MultiplayerRoot) -> int:
	return mp.get_service_channel_start(self)
