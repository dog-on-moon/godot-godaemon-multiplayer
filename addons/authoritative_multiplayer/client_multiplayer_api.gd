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
	print("Got RPC for %d: %s::%s(%s)" % [peer, object, method, args])
	return base_multiplayer.rpc(peer, object, method, args)

func _object_configuration_add(object, config: Variant) -> Error:
	return ERR_UNAVAILABLE

func _object_configuration_remove(object, config: Variant) -> Error:
	return ERR_UNAVAILABLE

func _set_multiplayer_peer(p_peer: MultiplayerPeer):
	base_multiplayer.multiplayer_peer = p_peer

func _get_multiplayer_peer() -> MultiplayerPeer:
	return base_multiplayer.multiplayer_peer

func _get_unique_id() -> int:
	return base_multiplayer.get_unique_id()

func _get_peer_ids() -> PackedInt32Array:
	return base_multiplayer.get_peers()
