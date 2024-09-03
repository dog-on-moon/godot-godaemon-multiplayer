extends MultiplayerAPIExtension
class_name GodaemonMultiplayer
## An extension of SceneMultiplayer, re-implementing its base overrides.

var multiplayer_node: MultiplayerNode

## Use this instead of get_remote_sender_id().
## Can also do MultiplayerNode.get_remote_sender_id()
var remote_sender: int = 0

#region SceneMultiplayer Overrides

signal peer_packet(id: int, packet: PackedByteArray)

var scene_multiplayer = SceneMultiplayer.new()

func _init():
	scene_multiplayer.connected_to_server.connect(connected_to_server.emit)
	scene_multiplayer.connection_failed.connect(connection_failed.emit)
	scene_multiplayer.peer_connected.connect(peer_connected.emit)
	scene_multiplayer.peer_disconnected.connect(peer_disconnected.emit)
	scene_multiplayer.peer_packet.connect(_recv_command)
	scene_multiplayer.server_relay = false

func _poll():
	return scene_multiplayer.poll()

func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	if object is not Node:
		return ERR_UNCONFIGURED
	return _outbound_rpc(peer, object, method, args)

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
	RPC = 1,  ## Re-route for RPCs
}

## Sends a command. The bytes array is modified.
func _send_command(command: NetCommand, bytes: PackedByteArray, id := 0, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0):
	bytes.append(command)
	scene_multiplayer.send_bytes(bytes, id, mode, channel)

## Receives a command.
func _recv_command(id: int, bytes: PackedByteArray):
	var command: NetCommand = bytes[-1]
	bytes.remove_at(bytes.size() - 1)
	match command:
		NetCommand.RAW:
			peer_packet.emit(id, bytes)
		NetCommand.RPC:
			remote_sender = id
			_inbound_rpc.callv([id] + bytes_to_var(bytes))
			remote_sender = 0

#endregion

#region RPCs

## An array of functions that modify the outbound RPC channel.
## They take the arguments:
## 	(channel: int, from_peer: int, to_peer: int, node: Node, method: StringName, args: Array) 
## The function will return the new channel.
var rpc_channel_modifiers: Array[Callable] = []

## An array of functions that are called on every outbound RPC.
## They take the arguments:
## 	(from_peer: int, to_peer: int, node: Node, method: StringName, args: Array) 
## The RPC is blocked if a filter function returns false.
var outbound_rpc_filters: Array[Callable] = []

## An array of functions that are called on every inbound RPC.
## They take the arguments:
## 	(from_peer: int, to_peer: int, node: Node, method: StringName, args: Array) 
## The RPC is blocked if a filter function returns false.
var inbound_rpc_filters: Array[Callable] = []

func _outbound_rpc(peer: int, node: Node, method: StringName, args: Array) -> Error:
	# Ensure there is a valid RPC config.
	var config: Dictionary = node.get_node_rpc_config()
	if method not in config:
		if node.get_script():
			config = node.get_script().get_rpc_config()
	if method not in config:
		push_error("GodaemonMultiplayer._outbound_rpc could not find RPC config")
		return ERR_UNCONFIGURED
	config = config[method]
	var rpc_mode: RPCMode = config.get("rpc_mode", RPC_MODE_AUTHORITY)
	var transfer_mode: MultiplayerPeer.TransferMode = config.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	var call_local: bool = config.get("call_local", false)
	var channel: int = config.get("channel", 0)
	
	# Validate node.
	var path := multiplayer_node.get_path_to(node)
	if not path:
		push_error("GodaemonMultiplayer._outbound_rpc could not find path to node")
		return ERR_UNAVAILABLE
	if not node.has_method(method):
		push_error("GodaemonMultiplayer._outbound_rpc node missing method %s" % method)
		return ERR_UNAVAILABLE
	if node[method].get_argument_count() != args.size():
		push_error("GodaemonMultiplayer._outbound_rpc mismatched argument counts: %s(%s)" % [method, args])
		return ERR_UNAVAILABLE
	
	# Process hooks.
	for modifier: Callable in rpc_channel_modifiers:
		channel = modifier.call(channel, get_unique_id(), peer, node, method, args)
	for filter: Callable in outbound_rpc_filters:
		if not filter.call(get_unique_id(), peer, node, method, args):
			return ERR_UNAVAILABLE
	
	# Perform local call.
	if call_local:
		node[method].callv(args)
	
	# Filter RPC through MultiplayerNode.
	var target_peer: int = 1 if multiplayer_node.is_client() else peer
	_send_command(NetCommand.RPC, var_to_bytes([peer, path, method, args]), target_peer, transfer_mode, channel)
	return OK

func _inbound_rpc(from_peer: int, to_peer: int, node_path: NodePath, method: StringName, args: Array):
	# Ensure node and callable can be found.
	var node := multiplayer_node.get_node_or_null(node_path)
	if not node:
		return
	if not node.has_method(method):
		return
	var callable: Callable = node[method].bindv(args)
	
	# Test ratelimit.
	if not check_rpc_ratelimit(node, method):
		return
	
	# Test filters.
	for filter: Callable in inbound_rpc_filters:
		if not filter.call(from_peer, to_peer, node, method, args):
			return
	
	# Call or re-route RPC.
	if to_peer == 1 or from_peer == 1:
		# This RPC is specifically for the server or from the server, so perform.
		callable.call()
	elif to_peer > 0:
		# OK, this RPC was designated for a specific target instead.
		# We will need to RPC it back to that peer.
		callable.rpc_id(to_peer)
	else:
		# This RPC was designed for everyone but a certain peer.
		var skip_peer := -to_peer
		if skip_peer != 1:
			callable.call()
		for p in get_peers():
			if p == skip_peer or p == 1:
				continue
			callable.rpc_id(p)

#endregion

#region Ratelimiting

var _node_rpc_ratelimits := {}

## Sets the ratelimit on a given RPC for a Node.
func set_rpc_ratelimit(node: Node, method: StringName, count: int, duration: float):
	_node_rpc_ratelimits.get_or_add(node, {})[method] = RateLimiter.new(multiplayer_node, count, duration)

## Tests the ratelimit on a given RPC for a Node.
func check_rpc_ratelimit(node: Node, method: StringName) -> bool:
	if node not in _node_rpc_ratelimits:
		return true
	if method not in _node_rpc_ratelimits[node]:
		return true
	var rl: RateLimiter = _node_rpc_ratelimits[node][method]
	var result := rl.check()
	if not result and OS.has_feature("editor"):
		push_warning("GodaemonMultiplayer: ratelimited RPC %s.%s()" % [node.name, method])
	return result

#endregion
