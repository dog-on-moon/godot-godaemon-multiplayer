extends ServiceBase
class_name SyncService
## Watches and syncs property changes within replicated scenes.

const REPCO = preload("res://addons/godaemon_multiplayer/services/replication/constants.gd")

## The ticks-per-second for updating interpolation fields.
const INTERPOLATE_TPS := 10.0
const INTERPOLATE_MSPT := (1.0 / INTERPOLATE_TPS) * 1000.0
const INTERPOLATE_DURATION := (1.0 / INTERPOLATE_TPS) * 1.1

var replication_service: ReplicationService

var last_interpolate_t := 0.0

func _enter_tree() -> void:
	replication_service = mp.get_service(ReplicationService)
	
	# Replicate property changes as the last event in the frame.
	process_priority = 100000
	replication_service.enter_replicated_scene.connect(enter_replicated_scene)
	replication_service.exit_replicated_scene.connect(exit_replicated_scene)
	
	if mp.is_server():
		mp.api.rpc.set_rpc_server_receive_only(self, &"_sv_receive_reliable_properties")
		mp.api.rpc.set_rpc_server_receive_only(self, &"_sv_receive_unreliable_properties")

#region Caches

func enter_replicated_scene(scene: Node):
	update_value_cache(scene)

func exit_replicated_scene(scene: Node):
	_scene_replication_data_cache.erase(scene)
	_scene_sender_data_cache.erase(scene)
	_scene_receiver_data_cache.erase(scene)
	_scene_reliable_data_cache.erase(scene)
	_replication_data_value_cache.erase(scene)

var _scene_replication_data_cache := {}

## Given a scene, returns an Array[[node, property path]].
func get_scene_replication_data(scene: Node, sync: REPCO.SyncMode) -> Array:
	if scene in _scene_replication_data_cache and sync in _scene_replication_data_cache[scene]:
		return _scene_replication_data_cache[scene][sync]
		
	var replication_data := []
	var replication_dict: Dictionary = scene.get_meta(REPCO.META_SYNC_PROPERTIES, {})
	for property_path: NodePath in replication_dict:
		var property_data: Array = replication_dict[property_path]
		var property_mode: REPCO.SyncMode = property_data[2]
		if sync != property_mode:
			continue
		
		# Find the node.
		var node_path := NodePath(property_path.get_concatenated_names())
		var node := scene.get_node(node_path) if node_path else scene
		if not node:
			replication_data.append([null, NodePath()])
			continue
		
		# Add to replication data.
		var prop_path := NodePath(property_path.get_concatenated_subnames())
		replication_data.append([node, prop_path])
	
	# Return cached value.
	_scene_replication_data_cache.get_or_add(scene, {})[sync] = replication_data
	return replication_data

var _scene_sender_data_cache := {}

## Returns an array of the sender data for each property.
func get_scene_sender_data(scene: Node) -> Array[REPCO.PeerFilter]:
	if scene in _scene_sender_data_cache:
		return _scene_sender_data_cache[scene]
	var sender_data: Array[REPCO.PeerFilter] = []
	var replication_dict: Dictionary = scene.get_meta(REPCO.META_SYNC_PROPERTIES, {})
	for property_path: NodePath in replication_dict:
		sender_data.append(replication_dict[property_path][0])
	_scene_sender_data_cache[scene] = sender_data
	return sender_data

var _scene_receiver_data_cache := {}

## Returns an array of the receiver data for each property.
func get_scene_receiver_data(scene: Node) -> Array[REPCO.PeerFilter]:
	if scene in _scene_receiver_data_cache:
		return _scene_receiver_data_cache[scene]
	var sender_data: Array[REPCO.PeerFilter] = []
	var replication_dict: Dictionary = scene.get_meta(REPCO.META_SYNC_PROPERTIES, {})
	for property_path: NodePath in replication_dict:
		sender_data.append(replication_dict[property_path][1])
	_scene_receiver_data_cache[scene] = sender_data
	return sender_data

var _scene_reliable_data_cache := {}

## Returns an array of the reliable data for each property.
func get_scene_reliable_data(scene: Node) -> Array[bool]:
	if scene in _scene_reliable_data_cache:
		return _scene_reliable_data_cache[scene]
	var reliable_data: Array[bool] = []
	var replication_dict: Dictionary = scene.get_meta(REPCO.META_SYNC_PROPERTIES, {})
	for property_path: NodePath in replication_dict:
		reliable_data.append(replication_dict[property_path][3])
	_scene_reliable_data_cache[scene] = reliable_data
	return reliable_data

#endregion

#region Sender Processing

const HARVEST_SYNCS: Array[REPCO.SyncMode] = [REPCO.SyncMode.ON_CHANGE, REPCO.SyncMode.INTERPOLATE_ON_CHANGE]
const HARVEST_RELIABLES: Array[bool] = [true, false]

var _rpc_scene: Node

func _process(delta: float) -> void:
	if mp.is_server():
		pass
	
	# Check if we are communicating interpolation on this frame.
	var msec := Time.get_ticks_msec()
	var is_interpolate_frame := msec > (last_interpolate_t + INTERPOLATE_MSPT)
	if is_interpolate_frame:
		last_interpolate_t = msec
	
	# Check every scene in the replication service.
	for scene: Node in replication_service.replicated_scenes:
		var node_id := mp.api.repository.get_id(scene)
		if node_id == -1:
			push_warning("Could not sync values for node %s: id missing" % scene)
			continue
		
		if scene is not Zone and mp.is_server() and scene.get_child_count() == 1 and 'press_count' in scene.get_child(0):
			pass
		
		# Harvest each sync and reliable mode.
		var changed := false
		_rpc_scene = scene
		for sync in HARVEST_SYNCS:
			if sync == REPCO.SyncMode.INTERPOLATE_ON_CHANGE and not is_interpolate_frame:
				continue
			for reliable in HARVEST_RELIABLES:
				for to_peer in ([1] if mp.is_client() else replication_service.get_observing_peers(scene)):
					var values := get_replication_data_values(scene, sync, to_peer, reliable)
					if not values:
						continue
					changed = true
					var data := _compress_values(node_id, sync, reliable, values)
					if not data:
						continue
					
					# var username_service: UsernameService = mp.get_service(UsernameService)
					# print('(%s, %s) updating %s properties with %s (=> %s)' % [sync, reliable, scene, values, username_service.get_username(to_peer)])
					# replication_service.get_observing_peers(scene)
					
					var rpc := _get_receive_rpc(reliable)
					rpc.rpc_id(to_peer, data)
		
		if changed:
			update_value_cache(scene)
	_rpc_scene = null

## A map between scene to array of property value.
var _replication_data_value_cache := {}

func _get_replication_data_value_cache(scene: Node) -> Array:
	var value_cache: Array = _replication_data_value_cache.get_or_add(scene, [])
	var size: int = scene.get_meta(REPCO.META_SYNC_PROPERTIES, {}).size()
	if value_cache.size() != size:
		value_cache.resize(size)
		value_cache.fill(null)
	return value_cache

## Given a whole bunch of area, harvest the current property values for replication.
## If a value should not be replicated, its index will be null.
func get_replication_data_values(scene: Node, sync: REPCO.SyncMode, to_peer: int, reliable: bool) -> Dictionary:
	var replication_data := get_scene_replication_data(scene, sync)
	var values := {}
	if not replication_data:
		return values
	var sender_data := get_scene_sender_data(scene)
	var receiver_data := get_scene_receiver_data(scene)
	var reliable_data := get_scene_reliable_data(scene)
	var value_cache := _get_replication_data_value_cache(scene)
	for idx in replication_data.size():
		# Skip if this isn't the right reliable mode.
		if reliable != reliable_data[idx]:
			continue
		
		var result: Variant = null
		
		# Check for a valid node.
		var node: Node = replication_data[idx][0]
		if not (node and is_instance_valid(node)):
			continue
		
		# If we're on client, avoid sending certain values.
		if mp.is_client():
			var send: REPCO.PeerFilter = sender_data[idx]
			if send == REPCO.PeerFilter.SERVER:
				continue
			elif send == REPCO.PeerFilter.OWNER_SERVER:
				var node_owner := REPCO.get_node_owner(node)
				if node_owner != mp.local_peer:
					continue
		
		# If we're on server, avoid sending certain values.
		elif mp.is_server():
			var recv: REPCO.PeerFilter = receiver_data[idx]
			if recv == REPCO.PeerFilter.SERVER:
				continue
			elif recv == REPCO.PeerFilter.OWNER_SERVER:
				var node_owner := REPCO.get_node_owner(node)
				if node_owner != to_peer:
					continue
		
		# If there's property interpolation active on this value,
		# we definitely don't want to re-write it on accident.
		var property_path: NodePath = replication_data[idx][1]
		if _has_property_interpolation(node, property_path):
			continue
		
		# Add result, only if it differs from cache.
		result = node.get_indexed(property_path)
		if value_cache[idx] != result:
			values[idx] = _compress_property_change(value_cache[idx], result)
	return values

## Updates values in the value cache for replication data.
func update_value_cache(scene: Node):
	var value_cache := _get_replication_data_value_cache(scene)
	for sync in HARVEST_SYNCS:
		var replication_data := get_scene_replication_data(scene, sync)
		if not replication_data:
			continue
		for idx in replication_data.size():
			var node: Node = replication_data[idx][0]
			if node and is_instance_valid(node):
				var property_path: NodePath = replication_data[idx][1]
				value_cache[idx] = node.get_indexed(property_path)

#endregion

#region Receiver Processing

#region RPC Funnel

func _get_receive_rpc(reliable: bool) -> Callable:
	if mp.is_client():
		if reliable:
			return _cl_receive_reliable_properties
		else:
			return _cl_receive_unreliable_properties
	else:
		if reliable:
			return _sv_receive_reliable_properties
		else:
			return _sv_receive_unreliable_properties

@rpc("reliable")
func _cl_receive_reliable_properties(data: PackedByteArray):
	_receive_properties(data)

@rpc("unreliable_ordered")
func _cl_receive_unreliable_properties(data: PackedByteArray):
	_receive_properties(data)

@rpc("any_peer", "reliable")
func _sv_receive_reliable_properties(data: PackedByteArray):
	_receive_properties(data)

@rpc("any_peer", "unreliable_ordered")
func _sv_receive_unreliable_properties(data: PackedByteArray):
	_receive_properties(data)

#endregion

func _receive_properties(data: PackedByteArray):
	var properties := _decompress_values(data)
	if not properties:
		return
	var node_id: int = properties[0]
	var scene := mp.api.repository.get_node(node_id)
	if not scene:
		push_warning("SyncService._receive_properties does not know node ID %s" % properties[0])
		return
	var sync: REPCO.SyncMode = properties[1]
	var reliable: bool = properties[2]
	var values: Dictionary = properties[3]
	
	var replication_data := get_scene_replication_data(scene, sync)
	var value_cache := _get_replication_data_value_cache(scene)
	var sender_data := get_scene_sender_data(scene)
	var receiver_data := get_scene_receiver_data(scene)
	var reliable_data := get_scene_reliable_data(scene)
	var updated_values := {}
	for idx in values:
		# Skip if this isn't the right reliable mode.
		if reliable != reliable_data[idx]:
			continue
		
		# Check for a valid node.
		var node: Node = replication_data[idx][0]
		if not node or not is_instance_valid(node):
			continue
		
		# If we're reading from the server, skip client-blocked values.
		var value: Variant = values[idx]
		if mp.is_server():
			var send: REPCO.PeerFilter = sender_data[idx]
			if send == REPCO.PeerFilter.SERVER:
				continue
			elif send == REPCO.PeerFilter.OWNER_SERVER:
				var node_owner := REPCO.get_node_owner(node)
				if node_owner != mp.remote_peer:
					continue
			else:
				updated_values[idx] = value
		
		# Get and set property value.
		var property_path: NodePath = replication_data[idx][1]
		var true_value: Variant = _decompress_property_change(values[idx], node, property_path)
		if sync == REPCO.SyncMode.ON_CHANGE:
			node.set_indexed(property_path, true_value)
		elif sync == REPCO.SyncMode.INTERPOLATE_ON_CHANGE:
			_start_property_interpolation(node, property_path, true_value)
		value_cache[idx] = value
	
	# If we're the server, forward the updated properties to other peers.
	if mp.is_server():
		var forward_data := _compress_values(node_id, sync, reliable, updated_values)
		if not forward_data:
			push_warning("Server could not forward property data")
			return
		var rpc := _get_receive_rpc(reliable)
		for peer in replication_service.get_observing_peers(scene):
			if peer == mp.remote_peer:
				continue
			
			# var username_service: UsernameService = mp.get_service(UsernameService)
			# print('(%s, %s) forwarding %s properties with %s (=> %s)' % [sync, reliable, scene, values, username_service.get_username(peer)])
			# replication_service.get_observing_peers(scene)
			
			rpc.rpc_id(peer, forward_data)

#region Compression

func _compress_values(node_id: int, sync: REPCO.SyncMode, reliable: bool, values: Dictionary) -> PackedByteArray:
	var stream := PackedByteStream.new()
	stream.setup_write(mp.api.repository.MAX_BYTES + 3)
	stream.write_unsigned(node_id, mp.api.repository.MAX_BYTES)
	stream.write_u8(sync)
	stream.write_u8(reliable)
	assert(values.size() <= 255, "Property sync tried writing too many values, What are you doing??")
	stream.write_u8(values.size())
	for idx in values:
		stream.allocate(1 + stream.get_var_size(values[idx]))
		stream.write_u8(idx)
		stream.write_variant(values[idx], mp.configuration.allow_object_decoding)
	if not stream.valid:
		push_warning("SyncService._compress_values was invalid")
		return PackedByteArray()
	return stream.data

func _decompress_values(data: PackedByteArray) -> Array:
	var results := []
	var stream := PackedByteStream.new()
	stream.setup_read(data)
	results.append(stream.read_unsigned(mp.api.repository.MAX_BYTES))
	results.append(stream.read_u8())
	results.append(stream.read_u8())
	var values_size := stream.read_u8()
	var values := {}
	for _i in values_size:
		var idx := stream.read_u8()
		var value := stream.read_variant(mp.configuration.allow_object_decoding)
		values[idx] = value
	results.append(values)
	if not stream.valid:
		push_warning("SyncService._decompress_values was invalid")
		return []
	return results

func _compress_property_change(old_value: Variant, new_value: Variant) -> Variant:
	var type := typeof(new_value)
	match type:
		TYPE_DICTIONARY:
			var added_values := {}
			var removed_keys := []
			for new in new_value:
				if new not in old_value:
					added_values[new] = new_value[new]
			for old in old_value:
				if old not in new_value:
					removed_keys.append(old)
			return new_value
		_:
			return new_value

func _decompress_property_change(variant: Variant, node: Node, property_path: NodePath) -> Variant:
	var value := node.get_indexed(property_path)
	var type := typeof(value)
	match type:
		TYPE_DICTIONARY:
			var added_values: Dictionary = variant[0]
			var removed_keys: Array = variant[1]
			var result: Dictionary = value.duplicate()
			for k in removed_keys:
				result.erase(k)
			result.merge(added_values)
			return result
		_:
			return variant

#endregion

#region Interpolation

var _property_interpolation_cache := {}

## Begins a property interpolation tween.
func _start_property_interpolation(node: Node, property_path: NodePath, value: Variant):
	_end_property_interpolation(node, property_path)
	var tween := node.create_tween()
	tween.tween_property(node, property_path, value, INTERPOLATE_DURATION)
	tween.tween_callback(_end_property_interpolation.bind(node, property_path))
	_property_interpolation_cache.get_or_add(node, {})[property_path] = tween
	node.tree_exited.connect(_node_exit_in_property_callback.bind(node), CONNECT_ONE_SHOT)

## Kills a property interpolation tween.
func _end_property_interpolation(node: Node, property_path: NodePath):
	if _has_property_interpolation(node, property_path):
		_property_interpolation_cache[node][property_path].kill()
	_property_interpolation_cache.get_or_add(node, {}).erase(property_path)
	node.tree_exited.disconnect(_node_exit_in_property_callback.bind(node))

func _node_exit_in_property_callback(node: Node):
	_property_interpolation_cache.erase(node)

## Returns true if a property interpolation is active.
func _has_property_interpolation(node: Node, property_path: NodePath) -> bool:
	return node in _property_interpolation_cache and property_path in _property_interpolation_cache[node]

#endregion

#endregion