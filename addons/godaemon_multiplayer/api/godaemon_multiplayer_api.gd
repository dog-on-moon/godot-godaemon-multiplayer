extends MultiplayerAPIExtension
class_name GodaemonMultiplayerAPI
## An extension of SceneMultiplayer, re-implementing its base overrides.


const Profiler = preload("res://addons/godaemon_multiplayer/api/profiler.gd")
const Repository = preload("res://addons/godaemon_multiplayer/api/repository.gd")
const Rpc = preload("res://addons/godaemon_multiplayer/api/rpc.gd")

var mp: MultiplayerRoot
var profiler: Profiler
var repository: Repository
var rpc: Rpc

func connected():
	profiler = Profiler.new(self)
	repository = Repository.new(self)
	rpc = Rpc.new(self)

func disconnected():
	profiler.cleanup()
	profiler = null
	repository.cleanup()
	repository = null
	rpc.cleanup()
	rpc = null
	mp = null
	scene_multiplayer.clear()
	multiplayer_peer.close()

#region SceneMultiplayer Overrides

signal peer_packet(id: int, packet: PackedByteArray)

var scene_multiplayer = SceneMultiplayer.new()

func _init():
	scene_multiplayer.connected_to_server.connect(connected_to_server.emit)
	scene_multiplayer.connection_failed.connect(connection_failed.emit)
	scene_multiplayer.peer_connected.connect(peer_connected.emit)
	scene_multiplayer.peer_disconnected.connect(peer_disconnected.emit)
	scene_multiplayer.peer_packet.connect(recv_command)
	scene_multiplayer.server_relay = false

func _poll():
	return scene_multiplayer.poll()

func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	if object is not Node:
		return ERR_UNCONFIGURED
	return rpc.outbound_rpc(peer, object, method, args)

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

func _get_remote_sender_id() -> int:
	return rpc.remote_sender

func send_packet(bytes: PackedByteArray, id := 0, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0):
	send_command(NetCommand.RAW, bytes, id, mode, channel)

#endregion

#region Communication

## The types of commands this MultiplayerAPI can send.
## (ensure this does not exceed 255)
enum NetCommand {
	RAW = 0,  ## Raw packets -- users can use this
	RPC = 1,  ## Re-route for RPCs
}

## Sends a command. The bytes array is modified.
func send_command(command: NetCommand, bytes: PackedByteArray, id := 0, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0):
	bytes.append(command)
	scene_multiplayer.send_bytes(bytes, id, mode, channel)

## Receives a command.
func recv_command(id: int, bytes: PackedByteArray):
	var command: NetCommand = bytes[-1]
	bytes.remove_at(bytes.size() - 1)
	match command:
		NetCommand.RAW:
			peer_packet.emit(id, bytes)
		NetCommand.RPC:
			rpc.inbound_rpc(id, bytes)

#endregion

#region Getters

var remote_sender: int:
	get: return get_remote_sender_id()

## Returns true if this is a client API.
func is_client() -> bool:
	return get_unique_id() != 1

## Returns true if this is a server API.
func is_server() -> bool:
	return get_unique_id() == 1

## Gets the owner ID of this node.
func get_node_owner(node: Node) -> int:
	return mp.get_node_owner(node)

## Returns true if the local peer owns this node.
func is_local_owner(node: Node) -> bool:
	return get_node_owner(node) == get_unique_id()

#endregion
