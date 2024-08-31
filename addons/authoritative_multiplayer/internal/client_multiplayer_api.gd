extends MultiplayerAPIExtension
class_name ClientMultiplayerAPI

var base_multiplayer = SceneMultiplayer.new()

func _init():
	base_multiplayer.connected_to_server.connect(connected_to_server.emit)
	base_multiplayer.connection_failed.connect(connection_failed.emit)
	base_multiplayer.peer_connected.connect(peer_connected.emit)
	base_multiplayer.peer_disconnected.connect(peer_disconnected.emit)

func _poll():
	return base_multiplayer.poll()

func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	if object is not Node:
		# Will only RPC on nodes
		return ERR_UNAUTHORIZED
	elif not MultiplayerManager.get_scene_name(object):
		# Undefined interest scene = treat as a usual RPC
		return base_multiplayer.rpc(peer, object, method, args)
	elif peer == 1:
		# Sending RPC to server only == passthrough OK
		return base_multiplayer.rpc(peer, object, method, args)
	elif peer <= 0:
		# Broadcasting RPC == RPC to all with object interest
		if object is not Node:
			return ERR_UNAUTHORIZED
		var skip_peer := 0 if peer == 0 else absi(peer)
		if skip_peer != 1:
			base_multiplayer.rpc(1, object, method, args)
		for p in MultiplayerManager.get_node_interest(object):
			if p == skip_peer:
				continue
			base_multiplayer.rpc(p, object, method, args)
		return OK
	else:
		# Sending RPC to specific peer == RPC to them if available
		if object is not Node:
			return ERR_UNAUTHORIZED
		if peer in MultiplayerManager.get_node_interest(object):
			return base_multiplayer.rpc(peer, object, method, args)
		else:
			return ERR_UNAUTHORIZED

func _object_configuration_add(object, config: Variant) -> Error:
	return base_multiplayer.object_configuration_add(object, config)

func _object_configuration_remove(object, config: Variant) -> Error:
	return base_multiplayer.object_configuration_remove(object, config)

func _set_multiplayer_peer(p_peer: MultiplayerPeer):
	base_multiplayer.multiplayer_peer = p_peer

func _get_multiplayer_peer() -> MultiplayerPeer:
	return base_multiplayer.multiplayer_peer

func _get_unique_id() -> int:
	return base_multiplayer.get_unique_id()

func _get_peer_ids() -> PackedInt32Array:
	return base_multiplayer.get_peers()
