extends RefCounted
## Provides an interface for RPCs for the GodaemonMultiplayerAPI.

## The max number of bits reserved for RPC methods.
## Turning this up will allow you to add more RPCs on a given object.
const MAX_RPC_METHOD_BITS := 8
const MAX_RPC_METHOD_BYTES := MAX_RPC_METHOD_BITS / 8
const MAX_RPC_METHODS := 2 ** MAX_RPC_METHOD_BITS

var api: GodaemonMultiplayerAPI

## An array of functions that modify the outbound RPC channel.
## They take the arguments:
## 	(channel: int, object: Object, transfer_mode: MultiplayerPeer.TransferMode) 
## The function will return the new channel.
var channel_modifiers: Array[Callable] = []

## An array of functions that are called on every outbound RPC.
## They take the arguments:
## 	(from_peer: int, target_peers: Array[int], object: Object, method: StringName, args: Array) 
## Modifying the target_peers array in-place will modify the target peers of the RPC.
var target_peer_modifiers: Array[Callable] = []

## An array of functions that are called on every outbound RPC.
## They take the arguments:
## 	(from_peer: int, to_peer: int, object: Object, method: StringName, args: Array) 
## The RPC is blocked if a filter function returns false.
var outbound_filters: Array[Callable] = []

## An array of functions that are called on every inbound RPC.
## They take the arguments:
## 	(from_peer: int, to_peer: int, object: Object, method: StringName, args: Array) 
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

func outbound_rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	if api.repository.get_id(object) == -1:
		push_error("Attempted to send RPC on untracked object: %s.\n
				Use mp.api.repository.add_object(obj, id), and ensure the id is matched on both server and client." % object)
		return ERR_CANT_RESOLVE
	
	# Ensure there is a valid RPC config.
	var config: Dictionary = {}
	if object.get_script():
		config.merge(object.get_script().get_rpc_config())
	config.merge(object.get_rpc_config())
	if method not in config:
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc could not find RPC config")
		return ERR_UNCONFIGURED
	var method_idx: int = config.keys().find(method)
	if method_idx >= MAX_RPC_METHODS:
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc method idx was too high")
		return ERR_UNCONFIGURED
	config = config[method]
	var rpc_mode: MultiplayerAPI.RPCMode = config.get("rpc_mode", MultiplayerAPI.RPC_MODE_AUTHORITY)
	if (api.mp.is_client() and rpc_mode != MultiplayerAPI.RPC_MODE_ANY_PEER) or rpc_mode == MultiplayerAPI.RPC_MODE_DISABLED:
		push_warning("GodaemonMultiplayerAPI.rpc.outbound_rpc Client attempted to send RPC on blocked method: %s.%s" % [object, method])
		return ERR_UNAUTHORIZED
	var transfer_mode: MultiplayerPeer.TransferMode = config.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	var call_local: bool = config.get("call_local", false)
	var channel: int = config.get("channel", 0)
	
	# Validate object.
	if not object.has_method(method):
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc object missing method %s" % method)
		return ERR_UNAVAILABLE
	if object[method].get_argument_count() != args.size():
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc mismatched argument counts: %s(%s)" % [method, args])
		return ERR_UNAVAILABLE
	
	# Process hooks.
	var from_peer := srs_override if srs_override != 0 else api.get_unique_id()
	channel = get_object_channel_override(object, channel)
	for modifier: Callable in channel_modifiers:
		channel = modifier.call(channel, object, transfer_mode)
	
	var target_peers: Array[int] = [peer]
	for modifier: Callable in target_peer_modifiers:
		modifier.call(from_peer, target_peers, object, method, args)
	for to_peer in target_peers:
		if to_peer == from_peer:
			continue
		
		var filtered := false
		for filter: Callable in outbound_filters:
			if not filter.call(from_peer, to_peer, object, method, args):
				filtered = true
				break
		if filtered:
			continue
		
		# Filter RPC through MultiplayerRoot.
		var bytes := compress_rpc(from_peer, to_peer, object, method_idx, args)
		if not bytes:
			continue
		var target_peer: int = 1 if api.is_client() else to_peer
		api.profiler.rpc(false, object.get_instance_id(), bytes.size() + 1)
		api.send_command(GodaemonMultiplayerAPI.NetCommand.RPC, bytes, target_peer, transfer_mode, channel)
	
	# Perform local call (we do it late so this callback won't interrupt the expected RPCing).
	# Also, if we're the server, only call local if SRS override is 0 (so the server doesnt also call local during forwarding)
	if call_local and (api.is_client() or srs_override == 0):
		remote_sender = api.get_unique_id()
		object[method].callv(args)
		remote_sender = 0
	
	# We're done.
	return OK

func inbound_rpc(id: int, bytes: PackedByteArray):
	# Read bytes.
	var data := decompress_rpc(id, bytes)
	if not data:
		return
	var from_peer:  int = data[0]
	var to_peer:    int = data[1]
	var object_id:  int = data[2]
	var method_idx: int = data[3]
	var args:     Array = data[4]
	
	# Ensure object and callable can be found.
	var object := api.repository.get_object(object_id)
	if not object:
		return
	var config: Dictionary = {}
	if object.get_script():
		config.merge(object.get_script().get_rpc_config())
	config.merge(object.get_rpc_config())
	if method_idx < 0 or method_idx >= config.size():
		return
	var method: StringName = config.keys()[method_idx]
	if not object.has_method(method) or method not in config:
		return
	var rpc_mode: MultiplayerAPI.RPCMode = config[method].get("rpc_mode", MultiplayerAPI.RPC_MODE_DISABLED)
	if (api.mp.is_server() and rpc_mode != MultiplayerAPI.RPC_MODE_ANY_PEER) or rpc_mode == MultiplayerAPI.RPC_MODE_DISABLED:
		push_warning("GodaemonMultiplayerAPI.rpc.inbound_rpc Client attempted to send RPC on blocked method: %s.%s" % [object, method])
		return
	var callable: Callable = object[method].bindv(args)
	
	# Test ratelimit.
	if not _check_rpc_ratelimit(from_peer, object, method):
		return
	
	# Test filters.
	for filter: Callable in inbound_filters:
		if not filter.call(from_peer, to_peer, object, method, args):
			return
	
	api.profiler.rpc(true, object.get_instance_id(), bytes.size())
	
	var method_is_server_only: bool = method in _object_rpc_server_receive_only.get(object, {})
	
	# Call or re-route RPC.
	remote_sender = from_peer
	if to_peer == 1 or id == 1:
		# This RPC is specifically for the server (client => server),
		# or this RPC is specifically from the server (server => client).
		callable.call()
	elif to_peer > 0:
		# This RPC is specifically from a client, but for another client (client => client)
		# So we will have to forward it back to that peer.
		if not method_is_server_only:
			srs_override = from_peer
			callable.rpc_id(to_peer)
			srs_override = 0
	else:
		# This is a broadcast RPC from a client, so we accept it ourselves,
		# and then forward it to all other clients.
		var skip_peer := -to_peer
		if skip_peer != 1:
			# Call it locally (if the target peer ID wasn't -1)
			callable.call()
		if not method_is_server_only:
			srs_override = from_peer
			for p in api.get_peers():
				# Don't forward the RPC to the skipped peer, ourselves, or to the sender
				if p == skip_peer or p == 1 or p == from_peer:
					continue
				callable.rpc_id(p)
			srs_override = 0
	remote_sender = 0

#endregion

#region RPC Serializer

func compress_rpc(from_peer: int, to_peer: int, object: Object, method_idx: int, args: Array) -> PackedByteArray:
	var stream := PackedByteStream.new()
	stream.setup_write(
		1  # header
		+ (4 if api.is_server() else 0)  # from_peer
		+ 4  # to_peer
		+ api.repository.MAX_BYTES  # object id
		+ MAX_RPC_METHOD_BYTES  # method id
	)
	
	# Determine header flags.
	var header_data := 0b00000000
	var packing_args := args.size() != 0
	if packing_args:
		header_data ^= 1
	var dense_args := args and args[0] is PackedByteArray
	if dense_args:
		header_data ^= 2
	stream.write_u8(header_data)
	
	# Writeout RPC properties.
	if api.is_server():
		stream.write_u32(from_peer)
	stream.write_u32(to_peer)
	
	var id := api.repository.get_id(object)
	if id == -1:
		push_warning("Attempted to send RPC on object without id: %s" % object)
		return PackedByteArray()
	stream.write_unsigned(id, api.repository.MAX_BYTES)
	
	# Encode method idx.
	if method_idx >= MAX_RPC_METHODS:
		push_warning("Attempted to send RPC on mode %s exceeding max methods: %s" % [object, MAX_RPC_METHODS])
		return PackedByteArray()
	stream.write_unsigned(method_idx, MAX_RPC_METHOD_BYTES)
	
	# Encode args.
	var data := stream.data
	if packing_args:
		if dense_args:
			data.append_array(args[0])
		else:
			var args_data := var_to_bytes(args)
			data.append_array(args_data)
	
	if not stream.valid:
		push_warning("Compressed RPC stream is invalid")
		return PackedByteArray()
	return data

func decompress_rpc(id: int, data: PackedByteArray) -> Array:
	var stream := PackedByteStream.new()
	stream.setup_read(data)
	
	# Decode header.
	var header := stream.read_u8()
	var packing_args := header & 1
	var dense_args := header & 2
	
	# Decode RPC properties.
	var from_peer := id
	if api.is_client():
		from_peer = stream.read_u32()
	var to_peer := stream.read_u32()
	var object_id := stream.read_unsigned(api.repository.MAX_BYTES)
	var method_idx := stream.read_unsigned(MAX_RPC_METHOD_BYTES)
	
	# Decode args, if present.
	var args := []
	if packing_args:
		if dense_args:
			args = [stream.data.slice(stream.c)]
		else:
			args = stream.read_variant(false)
	
	if not stream.valid:
		if OS.has_feature("debug"):
			push_warning("Decompressed RPC stream is invalid")
		return []
	return [from_peer, to_peer, object_id, method_idx, args]

#endregion

#region Override Object Channels

## Mapping of object to override channel.
var object_channels := {}

## Overrides the RPC channels on a given Object.
func set_object_channel_override(object: Object, channel: int):
	if object not in object_channels:
		object.tree_exited.connect(_clear_object_channel_override.bind(object), CONNECT_ONE_SHOT)
	object_channels[object] = channel

## Clears the channels set on a Object.
func _clear_object_channel_override(object: Object):
	object_channels.erase(object)

## Returns the channel of a Object.
func get_object_channel_override(object: Object, default_channel: int = 0) -> int:
	return object_channels.get(object, default_channel)

#endregion

#region RPC Ratelimits

var _object_rpc_ratelimits := {}

## Sets the ratelimit on a given RPC for a Object.
func set_rpc_ratelimit(object: Object, method: StringName, count: int, duration: float):
	var object_in_dict: bool = object in _object_rpc_ratelimits
	_object_rpc_ratelimits.get_or_add(object, {})[method] = RateLimiter.new(api.mp, count, duration)
	if not object_in_dict:
		object.tree_exited.connect(_clear_rpc_ratelimit.bind(object), CONNECT_ONE_SHOT)

## Tests the ratelimit on a given RPC for a Object.
func _check_rpc_ratelimit(peer: int, object: Object, method: StringName) -> bool:
	if object not in _object_rpc_ratelimits:
		return true
	if method not in _object_rpc_ratelimits[object]:
		return true
	var rl: RateLimiter = _object_rpc_ratelimits[object][method]
	var result := rl.check(peer)
	if not result and OS.has_feature("editor"):
		push_warning("GodaemonMultiplayerAPI: ratelimited RPC %s.%s() for peer %s" % [object.name, method, peer])
	return result

func _clear_rpc_ratelimit(object: Object):
	_object_rpc_ratelimits.erase(object)

#endregion

#region RPC Security

var _object_rpc_server_receive_only := {}

## Sets an RPC to only allow being received by the server.
## This will prevent clients from being able to send the RPC to other clients.
func set_rpc_server_receive_only(object: Object, method: StringName):
	if object not in _object_rpc_server_receive_only:
		_object_rpc_server_receive_only[object] = {}
		object.tree_exited.connect(_clear_object_rpc_server_receive_only.bind(object), CONNECT_ONE_SHOT)
	_object_rpc_server_receive_only[object][method] = null

func _clear_object_rpc_server_receive_only(object: Object):
	_object_rpc_server_receive_only.erase(object)

#endregion
