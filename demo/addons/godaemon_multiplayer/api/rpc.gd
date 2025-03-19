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
	api.peer_disconnected.connect(_peer_disconnected)

func cleanup():
	api = null

func _peer_disconnected(peer: int):
	peer_config_ratelimits.erase(peer)

#region RPCs

# Server Remote Sender Override
# Overrides the remote_sender that the client peer receives from their RPC.
# This is only applicable to the server.
var srs_override := 0

func outbound_rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	if not is_instance_valid(object):
		return ERR_CANT_RESOLVE
	await api.repository.await_for_id(api.mp.get_tree(), object)
	if not is_instance_valid(object):
		return ERR_CANT_RESOLVE
	if api.repository.get_id(object) == -1:
		push_error("Attempted to send RPC on untracked object: %s.\n
				Use mp.api.repository.add_object(obj, id), and ensure the id is matched on both server and client." % object)
		return ERR_CANT_RESOLVE
	
	if object.is_queued_for_deletion():
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc sent RPC on node %s queued for deletion" % object)
		return ERR_BUSY
	
	# Validate the config.
	var script := object.get_script()
	if not script:
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc attempted to send RPC on scriptless object....interesting.")
		return ERR_BUG
	
	var config := ReplicationData.object_method_to_config(object, String(method))
	if not config:
		#breakpoint
		ReplicationData.object_method_to_config(object, String(method))
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc attempted to send RPC on configless method %s" % [method])
		return ERR_UNCONFIGURED
	
	if object is Node and (not config.can_we_send(api.mp, object) and not api.mp.is_server()):
		push_error("Could not RPC protected method %s for server (%s)" % [method, script.resource_path])
		return ERR_UNCONFIGURED
	
	var method_idx: int = ReplicationData.object_method_to_idx(object, config)
	if method_idx >= MAX_RPC_METHODS or method_idx == -1:
		#breakpoint
		ReplicationData.object_method_to_idx(object, config)
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc method idx was invalid")
		return ERR_UNCONFIGURED
	
	# Validate object.
	if not object.has_method(method):
		push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc object missing method %s" % method)
		return ERR_UNAVAILABLE
	#if object[method].get_argument_count() != args.size():
		#breakpoint
		#push_error("GodaemonMultiplayerAPI.rpc.outbound_rpc mismatched argument counts: %s(%s)" % [method, args])
		#return ERR_UNAVAILABLE
	
	# Process hooks.
	var from_peer := srs_override if srs_override != 0 else api.get_unique_id()
	var transfer_mode := config.get_transfer_mode()
	var channel := get_object_channel_override(object, 0)
	for modifier: Callable in channel_modifiers:
		channel = modifier.call(channel, object, transfer_mode)
	
	# Determine target peers.
	var target_peers: Array[int] = [peer]
	if api.is_server():
		# The server has to do receive-filtering now, so that we don't
		# send an RPC to a client that they shouldn't be receiving --
		# (we trust the client to accept all RPCs they receive from the server).
		
		# Update target peers to be broadcasting in the anticipated way.
		if peer <= 0:
			target_peers.assign(api.get_peers())
			if peer < 0:
				target_peers.erase(-peer)
		
		# Filter out peers depending on recv tags.
		# We don't have to care about the server filter here.
		if object is Node:
			for p in target_peers.duplicate():
				if not config.can_they_recv(object, p):
					target_peers.erase(p)
		else:
			if not config.get_recv_filter_flag(ReplicationConfigBase.Filter.Client):
				target_peers.clear()
	
	# Perform target peer mods.
	for modifier: Callable in target_peer_modifiers:
		modifier.call(from_peer, target_peers, object, method, args)
	
	# RPC to all determined target peers.
	var debug_print := config.get_debug_print()
	for to_peer in target_peers:
		# Avoid calling the function to ourselves.
		if to_peer == from_peer:
			continue
		
		# Attempt to filter/block the RPC.
		var filtered := false
		for filter: Callable in outbound_filters:
			if not filter.call(from_peer, to_peer, object, method, args):
				filtered = true
				break
		if filtered:
			continue
		
		# Compress and send the RPC.
		var bytes := compress_rpc(from_peer, to_peer, object, method_idx, args)
		if not bytes:
			continue
		
		var target_peer: int = 1 if api.is_client() else to_peer
		api.profiler.rpc(false, object.get_instance_id(), bytes.size() + 1)
		api.send_command(GodaemonMultiplayerAPI.NetCommand.RPC, bytes, target_peer, transfer_mode, channel)
		
		if debug_print:
			if object is not SyncService:
				Log.info(self, "(%s => %s) sending RPC %s.%s (id: %s)" % [from_peer, to_peer, object.name, method, api.repository.get_id(object)])
	
	# Perform local call (we do it late so this callback won't interrupt the expected RPCing).
	# Also, if we're the server, only call local if SRS override is 0 (so the server doesnt also call local during forwarding)
	if config.get_call_local() and (api.is_client() or srs_override == 0):
		remote_sender = api.get_unique_id()
		object[method].callv(args)
		remote_sender = 0
	
	# We're done.
	return OK

func inbound_rpc(id: int, bytes: PackedByteArray):
	# Read bytes.
	var data := decompress_rpc(id, bytes)
	if not data:
		return ERR_UNCONFIGURED
	var from_peer:  int = data[0]
	var to_peer:    int = data[1]
	var object_id:  int = data[2]
	var method_idx: int = data[3]
	var args:     Array = data[4]
	
	# Ensure object and callable can be found.
	var object := api.repository.get_object(object_id)
	if not object:
		#breakpoint
		#push_error("GodaemonMultiplayerAPI.rpc.inbound_rpc received RPC for untracked object (p: %s, id %s)" % [api.local_peer, object_id])
		return ERR_UNCONFIGURED
	
	# Validate the config.
	var script := object.get_script()
	if not script:
		push_error("GodaemonMultiplayerAPI.rpc.inbound_rpc received to receive RPC on scriptless object....VERY interesting.")
		return ERR_BUG
	var config := ReplicationData.object_idx_to_method(object, method_idx)
	if not config:
		push_error("GodaemonMultiplayerAPI.rpc.inbound_rpc received RPC on configless method %s" % [method_idx])
		#breakpoint
		#ReplicationData.object_idx_to_method(object, method_idx)
		return ERR_UNCONFIGURED
	var method := config.name
	if not object.has_method(method):
		return ERR_UNCONFIGURED
	
	if config.get_debug_print():
		Log.info(self, "(%s => %s) receiving RPC %s.%s (id: %s)" % [from_peer, to_peer, object.name, method, object_id])
	
	var to_peer_is_owner := false
	if object is Node:
		to_peer_is_owner = to_peer == Godaemon.get_node_owner(object)
	
	# On the server, re-validate the send filters for this inbound RPC.
	if api.is_server() and object is Node:
		if not config.can_they_send(object, from_peer):
			push_error("Blocked received RPC %s for server (%s)" % [method, script.resource_path])
			return ERR_UNCONFIGURED
	
	# Test ratelimit.
	if not _check_rpc_ratelimit(from_peer, object, config):
		return
	
	# Test filters.
	for filter: Callable in inbound_filters:
		if not filter.call(from_peer, to_peer, object, method, args):
			return
	
	api.profiler.rpc(true, object.get_instance_id(), bytes.size())
	
	var method_is_server_only: bool = false
	
	# Call or re-route RPC.
	var callable: Callable = object[method].bindv(args)
	remote_sender = from_peer
	if to_peer == 1:
		# This RPC is specifically for the server (client => server).
		if config.get_recv_filter_flag(ReplicationConfigBase.Filter.Server):
			callable.call()
	elif id == 1:
		# This RPC is specifically from the server (server => client).
		# Server has already filtered recvs, so we can trust it.
		callable.call()
	elif to_peer > 0:
		# This RPC is specifically from a client, but for another client (client => client)
		# So we will have to forward it back to that peer.
		if object is Node:
			if config.can_they_recv(object, to_peer):
				srs_override = from_peer
				callable.rpc_id(to_peer)
				srs_override = 0
		else:
			if config.get_recv_filter_flag(ReplicationConfigBase.Filter.Client):
				srs_override = from_peer
				callable.rpc_id(to_peer)
				srs_override = 0
	else:
		# This is a broadcast RPC from a client, so we accept it ourselves,
		# and then forward it to all other clients.
		var skip_peer := -to_peer
		if skip_peer != 1:
			# Call it locally (if the target peer ID wasn't -1)
			if config.get_recv_filter_flag(ReplicationConfigBase.Filter.Server):
				callable.call()
		if not method_is_server_only and api:
			srs_override = from_peer
			for p in api.get_peers():
				# Don't forward the RPC to the skipped peer, ourselves, or to the sender
				if p == skip_peer or p == 1 or p == from_peer:
					continue
				
				if skip_peer > 0:
					var _skip := false
					for filter: Callable in inbound_filters:
						if not filter.call(from_peer, p, object, method, args):
							_skip = true
							break
					if _skip: continue
				
				if object is Node:
					if config.can_they_recv(object, p):
						callable.rpc_id(p)
				else:
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
	var dense_args := (args.size() == 1) and (args[0] is PackedByteArray)
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

var peer_config_ratelimits := {}

## Tests the ratelimit on a given RPC for a Object.
func _check_rpc_ratelimit(peer: int, object: Object, config: ReplicationMethodConfig) -> bool:
	if is_zero_approx(config.ratelimit):
		return true
	
	if peer not in peer_config_ratelimits:
		peer_config_ratelimits[peer] = {}
	if object not in peer_config_ratelimits[peer]:
		peer_config_ratelimits[peer][object] = {}
		if not object.freeing.is_connected(_clear_object_ratelimit.bind(object)):
			object.set_emit_freeing(true)
			object.freeing.connect(_clear_object_ratelimit.bind(object))
	if config not in peer_config_ratelimits[peer][object]:
		peer_config_ratelimits[peer][object][config] = RateLimiter.new(api.mp, 1, config.ratelimit)
	
	var rl: RateLimiter = peer_config_ratelimits[peer][object][config]
	var result := rl.check(peer)
	if not result and OS.has_feature("editor"):
		push_warning("GodaemonMultiplayerAPI: ratelimited RPC %s.%s() for peer %s" % [object, config.name, peer])
	return result

func _clear_object_ratelimit(obj: Object):
	for p: int in peer_config_ratelimits:
		peer_config_ratelimits[p].erase(obj)

#endregion
