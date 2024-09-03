extends Node
class_name PeerService
## This service allows the server to write out data for connected peers,
## which can be replicated back to all connected clients.
## Effectively a kind of replicated sketchbook for peer data.

## Emitted when any data has updated.
signal updated

## Emitted when any local data has updated.
signal local_updated

## Emitted when a peer's data is updated.
signal peer_updated(peer: int)

## Emitted when a peer's local data is updated.
signal peer_local_updated(peer: int)

## Emitted when data has fully resynced.
signal full_updated

## Emits data that is dropped upon a peer's disconnection.
signal peer_data_dropped(peer: int, data: Dictionary, local_data: Dictionary)

@onready var mp := MultiplayerNode.fetch(self)
static var SERVICE_CHANNELS := 1

## A dictionary from peer IDs to their data {}.
## This is replicated to all clients.
var peer_data := {}

## A dictionary from peer IDs to their local data {}.
var peer_local_data := {}

func _ready() -> void:
	mp.api.set_rpc_ratelimit(self, &"_request_sync", 1, 1.0)
	mp.peer_connected.connect(_peer_connected)
	mp.peer_disconnected.connect(_peer_disconnected)
	
	# Route these RPCs on a unique channel for the service.
	mp.api.rpc_channel_modifiers.append(
		func (channel: int, from_peer: int, to_peer: int, node: Node, method: StringName, args: Array):
			return channel if node != self else mp.get_service_channel_start(PeerService)
	)

func _peer_connected(peer: int):
	_sync.rpc_id(peer, peer_data)

func _peer_disconnected(peer: int):
	# We're dropping all of this data -- emit it in case anyone cares
	peer_data_dropped.emit(
		peer, peer_data.get(peer, {}),
		peer_local_data.get(peer, {})
	)
	peer_data.erase(peer)
	peer_local_data.erase(peer)

func get_peers(include_server := false) -> Array[int]:
	var peers: Array[int] = []
	peers.assign(mp.api.get_peers())
	if not include_server:
		peers.erase(1)
	return peers

#region Data Interface

## Adds data for a peer. Replicated to all clients.
func add_data(peer: int, key: Variant, value: Variant = null):
	assert(mp.is_server())
	peer_data.get_or_add(peer, {})[key] = value
	peer_updated.emit(peer)
	updated.emit()
	_sync_add_data.rpc(peer, key, value, peer_data.hash())

## Removes data from a peer. Replicated to all clients.
func remove_data(peer: int, key: Variant):
	assert(mp.is_server())
	peer_data.get_or_add(peer, {}).erase(key)
	peer_updated.emit(peer)
	updated.emit()
	_sync_remove_data.rpc(peer, key, peer_data.hash())

## Determines if a peer has some data set.
func has_data(peer: int, key: Variant) -> bool:
	return key in peer_data.get(peer, {})

## Gets the value of some data.
func get_data(peer: int, key: Variant, default: Variant = null) -> Variant:
	return peer_data.get(peer, {}).get(key, default)

## Returns all peers with the determined key/value.
func find_peers(key: Variant, value: Variant) -> Array[int]:
	var peers: Array[int] = []
	for peer in peer_data:
		if has_data(peer, key) and get_data(peer, key) == value:
			peers.append(peer)
	return peers

## Adds data for a peer. Only exists on the process.
func add_local_data(peer: int, key: Variant, value: Variant = null):
	peer_local_data.get_or_add(peer, {})[key] = value
	peer_local_updated.emit(peer)
	local_updated.emit()

## Removes local data from a peer.
func remove_local_data(peer: int, key: Variant):
	peer_local_data.get_or_add(peer, {}).erase(key)
	peer_local_updated.emit(peer)
	local_updated.emit()

## Determines if a peer has some local data set.
func has_local_data(peer: int, key: Variant) -> bool:
	return key in peer_local_data.get(peer, {})

## Gets the value of some local data.
func get_local_data(peer: int, key: Variant, default: Variant = null) -> Variant:
	return peer_local_data.get(peer, {}).get(key, default)

## Returns all peers with the determined key/value in local data.
func find_local_peers(key: Variant, value: Variant) -> Array[int]:
	var peers: Array[int] = []
	for peer in peer_local_data:
		if has_local_data(peer, key) and get_local_data(peer, key) == value:
			peers.append(peer)
	return peers

#endregion

#region Client Synchronization

@rpc("authority")
func _sync_add_data(peer: int, key: Variant, value: Variant, hash: int):
	peer_data.get_or_add(peer, {})[key] = value
	peer_updated.emit(peer)
	updated.emit()
	if peer_data.hash() != hash:
		_request_sync.rpc_id(1)

@rpc("authority")
func _sync_remove_data(peer: int, key: Variant, hash: int):
	peer_data.get_or_add(peer, {}).erase(key)
	peer_updated.emit(peer)
	updated.emit()
	if peer_data.hash() != hash:
		_request_sync.rpc_id(1)

@rpc("authority")
func _sync(_peer_data: Dictionary):
	peer_data = _peer_data
	updated.emit()
	full_updated.emit()

@rpc("any_peer")
func _request_sync():
	if not mp.is_server():
		return
	_sync.rpc_id(mp.get_remote_sender_id(), peer_data)

#endregion
