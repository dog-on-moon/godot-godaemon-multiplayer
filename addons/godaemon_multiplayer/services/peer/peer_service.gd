extends ServiceBase
class_name PeerService
## This service allows the server to write out data for connected peers,
## which can be replicated back to all connected clients.
## Effectively a kind of replicated sketchbook for peer data.

## Emitted when any data has updated.
signal updated

## Emitted when a peer's data is updated.
signal peer_updated(peer: int)

## Emitted when a peer's data is updated (for a specific key).
signal peer_key_updated(peer: int, key: Variant)

## Emitted when a peer's NON-SYNCED data is updated.
signal peer_updated_ns(peer: int)

## Emitted when a peer's NON-SYNCED data is updated (for a specific key).
signal peer_key_updated_ns(peer: int, key: Variant)

## Emitted when data has fully resynced.
signal full_updated

## Emits when a new peer is connected.
signal peer_connected(peer: int)

## Emits data that is dropped upon a peer's disconnection.
signal peer_data_dropped(peer: int, data: Dictionary)

## A dictionary from peer IDs to their data {}.
## This is replicated to all clients.
var peer_data := {}

## A dictionary that stores callbacks for when peer data information is changed
var peer_data_callbacks := {}

## A dictionary from peer IDs to their NON-SYNCED data {}.
## This is NOT replicated to clients.
var peer_data_ns := {}

## A dictionary that stores callbacks for when non-synced peer data information is changed
var peer_data_ns_callbacks := {}

func _ready() -> void:
	mp.peer_connected.connect(_peer_connected)
	mp.peer_disconnected.connect(_peer_disconnected)
	Godaemon.rpcs(self).set_rpc_ratelimit(self, &"_request_sync", 1, 1.0)
	Godaemon.rpcs(self).set_rpc_server_receive_only(self, &"_request_sync")

func _peer_connected(peer: int):
	peer_data[peer] = {}
	peer_data_ns[peer] = {}
	if mp.is_server() and peer != 1:
		_sync.rpc_id(peer, peer_data)

@rpc
func _peer_disconnected(peer: int):
	# We're dropping all of this data -- emit it in case anyone cares
	peer_data_dropped.emit(
		peer, peer_data.get(peer, {})
	)
	peer_data.erase(peer)
	peer_data_ns.erase(peer)

	# Remove any lingering callbacks
	if peer in peer_data_callbacks:
		peer_data_callbacks.erase(peer)
	if peer in peer_data_ns_callbacks:
		peer_data_ns_callbacks.erase(peer)

	if mp.is_server() and peer != 1:
		_peer_disconnected.rpc(peer)

## Returns all peer IDs. Includes the server.
func get_peers(include_server := true) -> Dictionary:
	if not include_server:
		var pd := peer_data.duplicate()
		pd.erase(1)
		return pd
	return peer_data

#region Data Interface

## Sets data for a peer. Replicated to all clients.
func set_data(peer: int, key: Variant, value: Variant = null):
	assert(mp.is_server())
	peer_data.get_or_add(peer, {})[key] = value
	for callback: Callable in peer_data_callbacks.get(peer, {}).get(key, []):
		callback.call()
	peer_key_updated.emit(peer, key)
	peer_updated.emit(peer)
	updated.emit()
	_sync_set_data.rpc(peer, key, value, peer_data.hash())

## Removes data from a peer. Replicated to all clients.
func remove_data(peer: int, key: Variant):
	assert(mp.is_server())
	peer_data.get_or_add(peer, {}).erase(key)
	for callback: Callable in peer_data_callbacks.get(peer, {}).get(key, []):
		callback.call()
	peer_key_updated.emit(peer, key)
	peer_updated.emit(peer)
	updated.emit()
	_sync_remove_data.rpc(peer, key, peer_data.hash())

## Determines if a peer has some data set.
func has_data(peer: int, key: Variant) -> bool:
	return key in peer_data.get(peer, {})

## Gets the value of some data.
func get_data(peer: int, key: Variant, default: Variant = null) -> Variant:
	return peer_data.get(peer, {}).get(key, default)

## Determines if the local client has some data set.
## Client only.
func has_local_data(key: Variant) -> bool:
	assert(mp.is_client())
	return has_data(multiplayer.get_unique_id(), key)

## Gets the value of some data on the local client.
## Client only.
func get_local_data(key: Variant, default: Variant = null) -> Variant:
	assert(mp.is_client())
	return get_data(multiplayer.get_unique_id(), key, default)

#region Non-synced Peer Data

## Sets data for a peer. NOT replicated.
func set_data_ns(peer: int, key: Variant, value: Variant = null):
	peer_data_ns.get_or_add(peer, {})[key] = value
	for callback: Callable in peer_data_ns_callbacks.get(peer, {}).get(key, []):
		callback.call()
	peer_key_updated_ns.emit(peer, key)
	peer_updated_ns.emit(peer)
	updated.emit()

## Removes data from a peer. NOT replicated.
func remove_data_ns(peer: int, key: Variant):
	peer_data_ns.get_or_add(peer, {}).erase(key)
	for callback: Callable in peer_data_ns_callbacks.get(peer, {}).get(key, []):
		callback.call()
	peer_key_updated_ns.emit(peer, key)
	peer_updated_ns.emit(peer)
	updated.emit()

## Determines if a peer has some non-synced data set.
func has_data_ns(peer: int, key: Variant) -> bool:
	return key in peer_data_ns.get(peer, {})

## Gets the value of some non-synced data.
func get_data_ns(peer: int, key: Variant, default: Variant = null) -> Variant:
	return peer_data_ns.get(peer, {}).get(key, default)

#endregion

## Returns all peers with the determined key/value.
func find_peers(key: Variant, value: Variant) -> Array[int]:
	var peers: Array[int] = []
	for peer in peer_data:
		if has_data(peer, key) and get_data(peer, key) == value:
			peers.append(peer)
	return peers

## Returns all peers with the determined NON-SYNCED key/value.
func find_peers_ns(key: Variant, value: Variant) -> Array[int]:
	var peers: Array[int] = []
	for peer in peer_data_ns:
		if has_data(peer, key) and get_data(peer, key) == value:
			peers.append(peer)
	return peers

#endregion

#region Client Synchronization

@rpc("authority")
func _sync_set_data(peer: int, key: Variant, value: Variant, hash: int):
	assert(mp.is_client())
	if peer not in peer_data:
		peer_connected.emit(peer)
	peer_data.get_or_add(peer, {})[key] = value
	for callback: Callable in peer_data_callbacks.get(peer, {}).get(key, []):
		callback.call()
	peer_key_updated.emit(peer, key)
	peer_updated.emit(peer)
	updated.emit()
	if peer_data.hash() != hash:
		_request_sync.rpc()

@rpc("authority")
func _sync_remove_data(peer: int, key: Variant, hash: int):
	assert(mp.is_client())
	peer_data.get_or_add(peer, {}).erase(key)
	for callback: Callable in peer_data_callbacks.get(peer, {}).get(key, []):
		callback.call()
	peer_key_updated.emit(peer, key)
	peer_updated.emit(peer)
	updated.emit()
	if peer_data.hash() != hash:
		_request_sync.rpc()

@rpc("authority")
func _sync(_peer_data: Dictionary):
	assert(mp.is_client())
	for peer in _peer_data:
		if peer not in peer_data:
			peer_connected.emit(peer)
	peer_data = _peer_data
	updated.emit()
	full_updated.emit()

@rpc("any_peer")
func _request_sync():
	assert(mp.is_server() and multiplayer.get_remote_sender_id() != 1)
	_sync.rpc_id(multiplayer.get_remote_sender_id(), peer_data)

#endregion

#region Dynamic data callbacks

## Adds a callback to automatically be called when a certain peer's key is updated.
func add_peer_data_callback(peer_id: int, key: StringName, callback: Callable, owner_node: Node = null) -> void:
	peer_data_callbacks.get_or_add(peer_id, {}).get_or_add(key, []).append(callback)
	
	if owner_node == null:
		owner_node = callback.get_object()
		assert(owner_node, "Please assign an owner object if using a lambda func. Thank you!")

	# TODO: Find a way to clean these up on peer disconnect
	owner_node.tree_exited.connect(func ():
		if peer_id not in peer_data_callbacks:
			return

		var callbacks: Array = peer_data_callbacks[peer_id][key]
		callbacks.erase(callback)
		if not callbacks:
			peer_data_callbacks[peer_id].erase(key)
			if not peer_data_callbacks[peer_id]:
				peer_data_callbacks.erase(peer_id)
		, CONNECT_ONE_SHOT
	)

## Adds a callback to automatically be called when a certain peer's key is updated on the NON-SYNCED version.
func add_peer_data_ns_callback(peer_id: int, key: StringName, callback: Callable, owner_node: Node = null) -> void:
	peer_data_ns_callbacks.get_or_add(peer_id, {}).get_or_add(key, []).append(callback)
	
	if owner_node == null:
		owner_node = callback.get_object()
		assert(owner_node, "Please assign an owner object if using a lambda func. Thank you!")

	# TODO: Find a way to clean these up on peer disconnect
	owner_node.tree_exited.connect(func ():
		if peer_id not in peer_data_callbacks:
			return

		var callbacks: Array = peer_data_ns_callbacks[peer_id][key]
		callbacks.erase(callback)
		if not callbacks:
			peer_data_ns_callbacks[peer_id].erase(key)
			if not peer_data_ns_callbacks[peer_id]:
				peer_data_ns_callbacks.erase(peer_id)
		, CONNECT_ONE_SHOT
	)

## An auto-filled local peer variant of add_peer_data_callback.
## Should only be used on the client.
func add_local_data_callback(key: StringName, callback: Callable, owner_node: Node = null) -> void:
	assert(mp.is_client())
	add_peer_data_callback(multiplayer.get_unique_id(), key, callback, owner_node)

#endregion
