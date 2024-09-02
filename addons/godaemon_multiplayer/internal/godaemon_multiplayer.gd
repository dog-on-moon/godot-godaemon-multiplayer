extends MultiplayerAPIExtension
class_name GodaemonMultiplayer
## An extension of SceneMultiplayer, re-implementing its base overrides.

#region SceneMultiplayer Overrides

signal peer_packet(id: int, packet: PackedByteArray)

var scene_multiplayer = SceneMultiplayer.new()

func _init():
	scene_multiplayer.connected_to_server.connect(connected_to_server.emit)
	scene_multiplayer.connection_failed.connect(connection_failed.emit)
	scene_multiplayer.peer_connected.connect(peer_connected.emit)
	scene_multiplayer.peer_disconnected.connect(peer_disconnected.emit)
	scene_multiplayer.peer_packet.connect(peer_packet.emit)

func _poll():
	return scene_multiplayer.poll()

func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	return scene_multiplayer._rpc(peer, object, method, args)
	#if object is not Node:
		## Will only RPC on nodes
		#return ERR_UNAUTHORIZED
	#elif not MultiplayerManager.get_scene_name(object):
		## Undefined interest scene = treat as a usual RPC
		#return scene_multiplayer._rpc(peer, object, method, args)
	#elif peer == 1:
		## Sending RPC to server only == passthrough OK
		#return scene_multiplayer._rpc(peer, object, method, args)
	#elif peer <= 0:
		## Broadcasting RPC == RPC to all with object interest
		#if object is not Node:
			#return ERR_UNAUTHORIZED
		#var skip_peer := 0 if peer == 0 else absi(peer)
		#if skip_peer != 1:
			#scene_multiplayer._rpc(1, object, method, args)
		#for p in MultiplayerManager.get_node_interest(object):
			#if p == skip_peer:
				#continue
			#scene_multiplayer._rpc(p, object, method, args)
		#return OK
	#else:
		## Sending RPC to specific peer == RPC to them if available
		#if object is not Node:
			#return ERR_UNAUTHORIZED
		#if peer in MultiplayerManager.get_node_interest(object):
			#return scene_multiplayer._rpc(peer, object, method, args)
		#else:
			#return ERR_UNAUTHORIZED

func _object_configuration_add(object, config: Variant) -> Error:
	return scene_multiplayer.object_configuration_add(object, config)

func _object_configuration_remove(object, config: Variant) -> Error:
	return scene_multiplayer.object_configuration_remove(object, config)

func _set_multiplayer_peer(p_peer: MultiplayerPeer):
	scene_multiplayer.multiplayer_peer = p_peer

func _get_multiplayer_peer() -> MultiplayerPeer:
	return scene_multiplayer.multiplayer_peer

func _get_unique_id() -> int:
	return scene_multiplayer.get_unique_id()

func _get_peer_ids() -> PackedInt32Array:
	return scene_multiplayer.get_peers()

func send_packet(bytes: PackedByteArray, id := 0, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0):
	_send_command(NetCommand.RAW, bytes, id, mode, channel)

#endregion

#region Communication

## The types of commands this MultiplayerAPI can send.
## (ensure this does not exceed 255)
enum NetCommand {
	RAW = 0,  ## Raw packets -- users can use this
}

## Sends a command. The bytes array is modified.
func _send_command(command: NetCommand, bytes: PackedByteArray, id := 0, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0):
	bytes.append(command)
	scene_multiplayer.send_bytes(bytes, id, mode, channel)

## Receives a command.
func _recv_command(id: int, bytes: PackedByteArray):
	var command: NetCommand = bytes[-1]
	bytes.remove_at(-1)
	match command:
		NetCommand.RAW:
			peer_packet.emit(id, bytes)

#endregion
