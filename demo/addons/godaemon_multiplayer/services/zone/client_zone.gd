extends Node
class_name ClientZone
## The representation of a zone on the client.

## Emitted when a peer has gained interest with this Zone.
signal interest_added(peer: int)

## Emitted when a peer has lost interest with this Zone.
signal interest_removed(peer: int)

#set by ZoneService
@onready var mp: MultiplayerRoot = Godaemon.mp(self)
@onready var zone_service := Godaemon.zone_service(self)

var old_interest := {}

## A dictionary mapping peers to null.
@export var interest := {}:
	set(x):
		interest = x
		if mp:
			for peer in interest:
				if peer not in old_interest:
					interest_added.emit(peer)
			for peer in old_interest:
				if peer not in interest:
					interest_removed.emit(peer)
			old_interest = x.duplicate()

@export var zone_index := 0

## Returns all peers with interest in this Zone.
func get_peers() -> Array[int]:
	var peers: Array[int] = []
	for p in interest:
		peers.append(p)
	return peers

## The scene we're in charge of.
var scene: Node

func _enter_tree() -> void:
	child_entered_tree.connect(
		func (s: Node):
			scene = s
			Godaemon.zone_service(self).local_client_add_interest(self)
			,
		CONNECT_ONE_SHOT)

func _exit_tree() -> void:
	zone_service.local_client_remove_interest(self)
