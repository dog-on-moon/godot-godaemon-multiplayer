extends MultiplayerAPIExtension
class_name GodaemonMultiplayerAPI
## An extension of SceneMultiplayer, re-implementing its base overrides.

var mp: MultiplayerRoot

## Use this instead of get_remote_sender_id().
## Can also do MultiplayerRoot.get_remote_sender_id()
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
	SERVICE = 2,  ## Service communications
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
			_inbound_rpc.callv(bytes_to_var(bytes))
			remote_sender = 0
		NetCommand.SERVICE:
			remote_sender = id
			_recv_service_message.call(bytes_to_var(bytes))
			remote_sender = 0

#endregion

#region RPCs

## Mapping of node to override channel.
var node_channels := {}

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
		push_error("GodaemonMultiplayerAPI._outbound_rpc could not find RPC config")
		return ERR_UNCONFIGURED
	config = config[method]
	var rpc_mode: RPCMode = config.get("rpc_mode", RPC_MODE_AUTHORITY)
	var transfer_mode: MultiplayerPeer.TransferMode = config.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	var call_local: bool = config.get("call_local", false)
	var channel: int = config.get("channel", 0)
	
	# Validate node.
	var path := mp.get_path_to(node)
	if not path:
		push_error("GodaemonMultiplayerAPI._outbound_rpc could not find path to node")
		return ERR_UNAVAILABLE
	if not node.has_method(method):
		push_error("GodaemonMultiplayerAPI._outbound_rpc node missing method %s" % method)
		return ERR_UNAVAILABLE
	if node[method].get_argument_count() != args.size():
		push_error("GodaemonMultiplayerAPI._outbound_rpc mismatched argument counts: %s(%s)" % [method, args])
		return ERR_UNAVAILABLE
	
	# Process hooks.
	channel = get_node_channel(node, channel)
	for modifier: Callable in rpc_channel_modifiers:
		channel = modifier.call(channel, get_unique_id(), peer, node, method, args)
	for filter: Callable in outbound_rpc_filters:
		if not filter.call(get_unique_id(), peer, node, method, args):
			return ERR_UNAVAILABLE
	
	# Perform local call.
	if call_local:
		node[method].callv(args)
	
	# Filter RPC through MultiplayerRoot.
	var target_peer: int = 1 if mp.is_client() else peer
	_send_command(NetCommand.RPC, var_to_bytes([peer, path, method, args]), target_peer, transfer_mode, channel)
	return OK

func _inbound_rpc(to_peer: int, node_path: NodePath, method: StringName, args: Array):
	# Ensure node and callable can be found.
	var node := mp.get_node_or_null(node_path)
	if not node:
		return
	if not node.has_method(method):
		return
	var callable: Callable = node[method].bindv(args)
	
	# Test ratelimit.
	var from_peer: int = remote_sender
	if not check_rpc_ratelimit(from_peer, node, method):
		return
	
	# Test filters.
	for filter: Callable in inbound_rpc_filters:
		if not filter.call(from_peer, to_peer, node, method, args):
			return
	
	var method_is_server_only: bool = method in _node_rpc_server_receive_only.get(node, {})
	
	# Call or re-route RPC.
	if to_peer == 1 or from_peer == 1:
		# This RPC is specifically for the server or from the server, so perform.
		callable.call()
	elif to_peer > 0:
		if not method_is_server_only:
			# OK, this RPC was designated for a specific target instead.
			# We will need to RPC it back to that peer.
			callable.rpc_id(to_peer)
	else:
		# This RPC was designed for everyone but a certain peer.
		var skip_peer := -to_peer
		if skip_peer != 1:
			callable.call()
		if not method_is_server_only:
			for p in get_peers():
				if p == skip_peer or p == 1 or p == from_peer:
					continue
				callable.rpc_id(p)

## Overrides the RPC channels on a given Node.
## Make sure to clean up in exit_tree.
func set_node_channel(node: Node, channel: int):
	node_channels[node] = channel
	node.tree_exited.connect(clear_node_channel.bind(node), CONNECT_ONE_SHOT)

## Clears the channels set on a Node.
func clear_node_channel(node: Node):
	node_channels.erase(node)

## Returns the channel of a Node.
func get_node_channel(node: Node, default_channel: int) -> int:
	return node_channels.get(node, default_channel)

#endregion

#region Service Commands

## Sends a message for a given service.
## The service on target peers will be called with ServiceBase.recv_message(args).
func send_service_message(service_name: StringName, args: Variant, peer := 0, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := 0):
	var data := var_to_bytes([service_name, args, peer, mode, channel])
	_send_command(NetCommand.SERVICE, data, peer if mp.is_server() else 1, mode, channel)

func _recv_service_message(data: Array):
	var service_name: StringName = data[0]
	var service: ServiceBase = mp.get_service_from_name(service_name)
	if not service:
		return
		
	var args: Variant = data[1]
	var to_peer: int = data[2]
	
	# Call or re-route service message.
	if to_peer == 1 or remote_sender == 1:
		service.recv_message(args)
	else:
		var mode: MultiplayerPeer.TransferMode = data[3]
		var channel: int = data[4]
		if to_peer > 0:
			send_service_message(service_name, args, to_peer, mode, channel)
		else:
			var skip_peer := -to_peer
			if skip_peer != 1:
				service.recv_message(args)
			for p in get_peers():
				if p == skip_peer or p == 1 or p == remote_sender:
					continue
				send_service_message(service_name, args, p, mode, channel)

#endregion

#region Ratelimiting

var _node_rpc_ratelimits := {}

## Sets the ratelimit on a given RPC for a Node.
func set_rpc_ratelimit(node: Node, method: StringName, count: int, duration: float):
	_node_rpc_ratelimits.get_or_add(node, {})[method] = RateLimiter.new(mp, count, duration)
	node.tree_exited.connect(clear_rpc_ratelimit.bind(node), CONNECT_ONE_SHOT)

## Tests the ratelimit on a given RPC for a Node.
func check_rpc_ratelimit(peer: int, node: Node, method: StringName) -> bool:
	if node not in _node_rpc_ratelimits:
		return true
	if method not in _node_rpc_ratelimits[node]:
		return true
	var rl: RateLimiter = _node_rpc_ratelimits[node][method]
	var result := rl.check(peer)
	if not result and OS.has_feature("editor"):
		push_warning("GodaemonMultiplayerAPI: ratelimited RPC %s.%s()" % [node.name, method])
	return result

func clear_rpc_ratelimit(node: Node):
	_node_rpc_ratelimits.erase(node)

#endregion

#region Security

var _node_rpc_server_receive_only := {}

## Sets an RPC to only allow being received by the server.
## This will prevent the server from routing blocked RPCs back out to clients.
func set_rpc_server_receive_only(node: Node, method: StringName):
	_node_rpc_server_receive_only.get_or_add(node, {})[method] = null
	node.tree_exited.connect(_clear_node_rpc_server_receive_only.bind(node), CONNECT_ONE_SHOT)

func _clear_node_rpc_server_receive_only(node: Node):
	_node_rpc_server_receive_only.erase(node)

#endregion
