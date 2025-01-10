extends SubViewport
class_name Zone
## A Zone is a high-level replicated scene, containerizing its world within a Viewport.
## You can access the Zone that any node lives in via Godaemon.zone(Node).

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
		if sync_service:
			sync_service.mark_dirty(self)

@export var zone_index := 0

## Returns all peers with interest in this Zone.
func get_peers() -> Array[int]:
	var peers: Array[int] = []
	for p in interest:
		peers.append(p)
	return peers

## The scene we're in charge of.
var scene: Node

#endregion

@onready var sync_service := Godaemon.sync_service(self)

func setup(sync_service: SyncService):
	sync_service.set_manual_tracking(self)
	world_2d = World2D.new()
	world_3d = World3D.new()

## Shorthand for ZoneService.add_interest
func add_interest(peer: int):
	return zone_service.add_interest(peer, self)

## Shorthand for ZoneService.remove_interest
func remove_interest(peer: int) -> bool:
	return zone_service.remove_interest(peer, self)

## Shorthand for ZoneService.has_interest
func has_interest(peer: int) -> bool:
	return zone_service.has_interest(peer, self)

## Shorthand for ZoneService.remove_zone
func remove() -> bool:
	return zone_service.remove_zone(self)
