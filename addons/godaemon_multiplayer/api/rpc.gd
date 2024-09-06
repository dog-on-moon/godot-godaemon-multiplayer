extends RefCounted
## Provides an interface for RPCs for the GodaemonMultiplayerAPI.

## The max number of bits reserved for RPC methods.
## Turning this up will allow you to add more RPCs on a given node.
const MAX_RPC_METHOD_BITS := 8
const MAX_RPC_METHODS := 2 ** MAX_RPC_METHOD_BITS

var api: GodaemonMultiplayerAPI

## An array of functions that modify the outbound RPC channel.
## They take the arguments:
## 	(channel: int, node: Node, transfer_mode: MultiplayerPeer.TransferMode) 
## The function will return the new channel.
var channel_modifiers: Array[Callable] = []

## An array of functions that are called on every outbound RPC.
## They take the arguments:
## 	(from_peer: int, target_peers: Array[int], node: Node, method: StringName, args: Array) 
## Modifying the target_peers array in-place will modify the target peers of the RPC.
var target_peer_modifiers: Array[Callable] = []

## An array of functions that are called on every outbound RPC.
## They take the arguments:
## 	(from_peer: int, to_peer: int, node: Node, method: StringName, args: Array) 
## The RPC is blocked if a filter function returns false.
var outbound_filters: Array[Callable] = []

## An array of functions that are called on every inbound RPC.
## They take the arguments:
## 	(from_peer: int, to_peer: int, node: Node, method: StringName, args: Array) 
## The RPC is blocked if a filter function returns false.
var inbound_filters: Array[Callable] = []

## The remote sender for a given RPC.
var remote_sender: int = 0

func _init(_api: GodaemonMultiplayerAPI):
	api = _api

func cleanup():
	api = null

#region RPCs

# Server Remote Sender Override
# Overrides the remote_sender that the client peer receives from their RPC.
# This is only applicable to the server.
var srs_override := 0

func outbound_rpc(peer: int, node: Node, method: StringName, args: Array) -> Error:
	if api.repository.get_id(node) == -1:
		push_error("Attempted to send RPC on untracked node: %s.\n
				Use mp.api.repository.add_node(node, id), and ensure the id is matched on both server and client." % node)
		return ERR_CANT_RESOLVE
	
	# Ensure there is a valid RPC config.
	var config: Dictionary = {}
	if node.get_script():
		config.merge(node.get_script().get_rpc_config())
	config.merge(node.get_node_rpc_config())
	if method not in config:
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc could not find RPC config")
		return ERR_UNCONFIGURED
	var method_idx: int = config.keys().find(method)
	if method_idx >= MAX_RPC_METHODS:
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc method idx was too high")
		return ERR_UNCONFIGURED
	config = config[method]
	var rpc_mode: MultiplayerAPI.RPCMode = config.get("rpc_mode", MultiplayerAPI.RPC_MODE_AUTHORITY)
	var transfer_mode: MultiplayerPeer.TransferMode = config.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	var call_local: bool = config.get("call_local", false)
	var channel: int = config.get("channel", 0)
	
	# Validate node.
	var node_path := api.mp.get_path_to(node)
	if not node_path:
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc could not find path to node")
		return ERR_UNAVAILABLE
	if not node.has_method(method):
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc node missing method %s" % method)
		return ERR_UNAVAILABLE
	if node[method].get_argument_count() != args.size():
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc mismatched argument counts: %s(%s)" % [method, args])
		return ERR_UNAVAILABLE
	
	# Process hooks.
	var from_peer := srs_override if srs_override != 0 else api.get_unique_id()
	channel = get_node_channel_override(node, channel)
	for modifier: Callable in channel_modifiers:
		channel = modifier.call(channel, node, transfer_mode)
	
	var target_peers: Array[int] = [peer]
	for modifier: Callable in target_peer_modifiers:
		modifier.call(from_peer, target_peers, node, method, args)
	for to_peer in target_peers:
		for filter: Callable in outbound_filters:
			if not filter.call(from_peer, to_peer, node, method, args):
				return ERR_UNAVAILABLE
		
		# Perform local call.
		if call_local:
			node[method].callv(args)
		if to_peer == from_peer:
			continue
		
		# Filter RPC through MultiplayerRoot.
		
		var bytes := compress_rpc(from_peer, to_peer, node, method_idx, args)
		var target_peer: int = 1 if api.is_client() else to_peer
		api.profiler.rpc(false, node.get_instance_id(), bytes.size() + 1)
		api.send_command(GodaemonMultiplayerAPI.NetCommand.RPC, bytes, target_peer, transfer_mode, channel)
	return OK

func inbound_rpc(id: int, bytes: PackedByteArray):
	# Read bytes.
	var data := decompress_rpc(bytes)
	if not data:
		return
	var from_peer: int = data.get('from_peer')
	var to_peer: int = data.get('to_peer')
	var node_id: int = data.get('node_id')
	var method_idx: int = data.get('method_idx')
	var args: Array = data.get('args')
	
	# Ensure node and callable can be found.
	var node := api.repository.get_node(node_id)
	if not node:
		return
	var config: Dictionary = {}
	if node.get_script():
		config.merge(node.get_script().get_rpc_config())
	config.merge(node.get_node_rpc_config())
	var method: StringName = config.keys()[method_idx]
	if not node.has_method(method):
		return
	var rpc_mode: MultiplayerAPI.RPCMode = config[method].get("rpc_mode", MultiplayerAPI.RPC_MODE_AUTHORITY)
	if api.mp.is_server() and rpc_mode != MultiplayerAPI.RPC_MODE_ANY_PEER:
		push_warning("GodaemonMultiplayerAPI.rpc.inbound_rpc Client attempted to send RPC on blocked method: %s.%s" % [node, method])
		return
	var callable: Callable = node[method].bindv(args)
	
	# Test ratelimit.
	if not _check_rpc_ratelimit(from_peer, node, method):
		return
	
	# Test filters.
	for filter: Callable in inbound_filters:
		if not filter.call(from_peer, to_peer, node, method, args):
			return
	
	api.profiler.rpc(true, node.get_instance_id(), bytes.size())
	
	var method_is_server_only: bool = method in _node_rpc_server_receive_only.get(node, {})
	
	# Call or re-route RPC.
	remote_sender = id
	if to_peer == 1:
		# This RPC is specifically for the server.
		callable.call()
	elif remote_sender == 1:
		# This RPC is on and for the client, so call with the true remote sender
		remote_sender = from_peer
		callable.call()
	elif to_peer > 0:
		if not method_is_server_only:
			# OK, this RPC was designated for a specific target instead.
			# We will need to RPC it back to that peer.
			srs_override = from_peer
			callable.rpc_id(to_peer)
			srs_override = 0
	else:
		# This RPC was designed for everyone but a certain peer.
		var skip_peer := -to_peer
		if skip_peer != 1:
			callable.call()
		if not method_is_server_only:
			srs_override = from_peer
			for p in api.get_peers():
				if p == skip_peer or p == 1 or p == from_peer:
					continue
				callable.rpc_id(p)
			srs_override = 0
	remote_sender = 0

#endregion

#region RPC Serializer

func compress_rpc(from_peer: int, to_peer: int, node: Node, method_idx: int, args: Array) -> PackedByteArray:
	var data := PackedByteArray()
	var s := 0
	
	# Encode from_peer.
	if api.is_server():
		s = data.size()
		data.resize(s + 4)
		data.encode_u32(s, from_peer)
	
	# Encode to_peer.
	s = data.size()
	data.resize(s + 4)
	data.encode_u32(s, to_peer)
	
	# Encode node.
	var id := api.repository.get_id(node)
	assert(id != -1)
	match api.repository.MAX_BITS:
		8:
			s = data.size()
			data.resize(s + 1)
			data.encode_u8(s, id)
		16:
			s = data.size()
			data.resize(s + 2)
			data.encode_u16(s, id)
		32:
			s = data.size()
			data.resize(s + 4)
			data.encode_u32(s, id)
		64:
			s = data.size()
			data.resize(s + 8)
			data.encode_s64(s, id)
		_:
			assert(false)
	
	# Encode method idx.
	assert(method_idx < MAX_RPC_METHODS)
	match MAX_RPC_METHOD_BITS:
		8:
			s = data.size()
			data.resize(s + 1)
			data.encode_u8(s, method_idx)
		16:
			s = data.size()
			data.resize(s + 2)
			data.encode_u16(s, method_idx)
		32:
			s = data.size()
			data.resize(s + 4)
			data.encode_u32(s, method_idx)
		64:
			s = data.size()
			data.resize(s + 8)
			data.encode_s64(s, method_idx)
		_:
			assert(false)
	
	# Encode args.
	if args:
		var args_data := var_to_bytes(args) if not api.mp.configuration.allow_object_decoding else var_to_bytes_with_objects(args)
		data.append_array(args_data)
	
	return data

func decompress_rpc(data: PackedByteArray) -> Dictionary:
	var s := 0
	
	# Decode from_peer.
	var from_peer := api.get_remote_sender_id()
	if api.is_client():
		from_peer = data.decode_u32(s)
		s += 4
	
	# Decode to_peer.
	var to_peer := data.decode_u32(s)
	s += 4
	
	# Decode node id.
	var node_id := 0
	match api.repository.MAX_BITS:
		8:
			node_id = data.decode_u8(s)
			s += 1
		16:
			node_id = data.decode_u16(s)
			s += 2
		32:
			node_id = data.decode_u32(s)
			s += 4
		64:
			node_id = data.decode_s64(s)
			s += 8
		_:
			assert(false)
	
	# Decode method idx.
	var method_idx := 0
	assert(method_idx < MAX_RPC_METHODS)
	match MAX_RPC_METHOD_BITS:
		8:
			method_idx = data.decode_u8(s)
			s += 1
		16:
			method_idx = data.decode_u16(s)
			s += 2
		32:
			method_idx = data.decode_u32(s)
			s += 4
		64:
			method_idx = data.decode_s64(s)
			s += 8
		_:
			assert(false)
	
	# Decode args, if present.
	var args := []
	if s < data.size():
		args = data.decode_var(s, api.mp.configuration.allow_object_decoding)
	
	return {
		'from_peer': from_peer,
		'to_peer': to_peer,
		'node_id': node_id,
		'method_idx': method_idx,
		'args': args,
	}

#endregion

#region Override Node Channels

## Mapping of node to override channel.
var node_channels := {}

## Overrides the RPC channels on a given Node.
func set_node_channel_override(node: Node, channel: int):
	if node not in node_channels:
		node.tree_exited.connect(_clear_node_channel_override.bind(node), CONNECT_ONE_SHOT)
	node_channels[node] = channel

## Clears the channels set on a Node.
func _clear_node_channel_override(node: Node):
	node_channels.erase(node)

## Returns the channel of a Node.
func get_node_channel_override(node: Node, default_channel: int = 0) -> int:
	return node_channels.get(node, default_channel)

#endregion

#region RPC Ratelimits

var _node_rpc_ratelimits := {}

## Sets the ratelimit on a given RPC for a Node.
func set_rpc_ratelimit(node: Node, method: StringName, count: int, duration: float):
	_node_rpc_ratelimits.get_or_add(node, {})[method] = RateLimiter.new(api.mp, count, duration)
	node.tree_exited.connect(_clear_rpc_ratelimit.bind(node), CONNECT_ONE_SHOT)

## Tests the ratelimit on a given RPC for a Node.
func _check_rpc_ratelimit(peer: int, node: Node, method: StringName) -> bool:
	if node not in _node_rpc_ratelimits:
		return true
	if method not in _node_rpc_ratelimits[node]:
		return true
	var rl: RateLimiter = _node_rpc_ratelimits[node][method]
	var result := rl.check(peer)
	if not result and OS.has_feature("editor"):
		push_warning("GodaemonMultiplayerAPI: ratelimited RPC %s.%s()" % [node.name, method])
	return result

func _clear_rpc_ratelimit(node: Node):
	_node_rpc_ratelimits.erase(node)

#endregion

#region RPC Security

var _node_rpc_server_receive_only := {}

## Sets an RPC to only allow being received by the server.
## This will prevent the server from routing blocked RPCs back out to clients.
func set_rpc_server_receive_only(node: Node, method: StringName):
	_node_rpc_server_receive_only.get_or_add(node, {})[method] = null
	node.tree_exited.connect(_clear_node_rpc_server_receive_only.bind(node), CONNECT_ONE_SHOT)

func _clear_node_rpc_server_receive_only(node: Node):
	_node_rpc_server_receive_only.erase(node)

#endregion
