extends ServiceBase
class_name ReplicationService
## Tracks the creation of replicated scenes, whose existence can be
## replicated to clients and controlled using visibility.
## This also tracks added nodes for RPCs and replicates their IDs to clients.

signal node_owner_updated(node: Node)

signal enter_replicated_scene(scene: Node)
signal exit_replicated_scene(scene: Node)

const REPCO = preload("res://addons/godaemon_multiplayer/services/replication/constants.gd")

## A dictionary map of replicated scenes to their peer visibility states.
var replicated_scenes := {}

func _enter_tree() -> void:
	# Look for existing replicated scenes, setup initial signals.
	_replicated_scene_search(mp)
	if mp.is_server():
		mp.peer_connected.connect(_peer_connected)
		mp.peer_disconnected.connect(_peer_disconnected)
		Godaemon.rpcs(self).target_peer_modifiers.append(_target_peer_modifier)
		Godaemon.rpcs(self).outbound_filters.append(_rpc_filter)

func _peer_connected(peer: int):
	# Peers need to know what initial scenes must be replicated to them.
	var added_nodes: Array[Node] = []
	for node in get_visible_nodes_for_peer(peer):
		added_nodes.append(node)
	_update_visibility(peer, added_nodes, [])

func _peer_disconnected(peer: int):
	for visibility_dict in replicated_scenes.values():
		visibility_dict.erase(peer)
	for visibility_dict in _visibility_cache.values():
		visibility_dict.erase(peer)

#region Service Internals

func _target_peer_modifier(from_peer: int, target_peers: Array[int], node: Node, method: StringName, args: Array):
	if node in replicated_scenes:
		var valid_peers := get_observing_peers(node)
		if target_peers == [0]:
			target_peers.clear()
			for p in valid_peers:
				target_peers.append(p)
		elif not target_peers:
			return
		elif target_peers[0] > 0:
			target_peers.assign(target_peers.filter(func (p: int): return p in valid_peers))
		else:
			var skip_peer: int = -target_peers[0]
			target_peers.assign(target_peers.filter(func (p: int): return p in valid_peers and p != skip_peer))

func _rpc_filter(from_peer: int, to_peer: int, node: Node, method: StringName, args: Array):
	if node in replicated_scenes:
		var valid_peers := get_observing_peers(node)
		if from_peer != 1 and from_peer not in valid_peers:
			return false
		if to_peer != 1 and to_peer not in valid_peers:
			return false
	return true

#endregion

#region Replication Setup

# Searches for replicated scenes.
func _replicated_scene_search(node: Node):
	# Only ever scan a node once
	if node.child_entered_tree.is_connected(_node_child_entered_tree):
		return
	
	# Only the server will catalog IDs and replicated scenes,
	# but will tell the client them during replication.
	# The client will still use the exit trees below to cleanup leaving IDs
	if mp.is_server():
		# Setup RPC index.
		if mp.api.repository.get_id(node) == -1:
			mp.api.repository.add_node(node)
		
		# Does this node have replicated properties?
		const key := REPCO.META_REPLICATE_SCENE
		if node.has_meta(key) and node not in replicated_scenes:
			# Register the node, and set its default global replication.
			# Node.owner will only be set at this point if the replicated scene
			# is instantiated within another replicated scene, so we assume
			# those to be TRUE by default and then simply DELETE them later on client replication.
			replicated_scenes[node] = {1: node.owner in replicated_scenes}
			enter_replicated_scene.emit(node)
	
	# Setup signals on this node.
	node.child_entered_tree.connect(_node_child_entered_tree)
	node.tree_exiting.connect(_node_tree_exiting.bind(node), CONNECT_ONE_SHOT)
	
	# Continue iteration.
	if node.is_node_ready():
		for child in node.get_children():
			_replicated_scene_search(child)

func _node_tree_exiting(node: Node):
	if node in replicated_scenes:
		if mp.api:
			for peer in get_observing_peers(node):
				_update_visibility(peer, [], [node])
		replicated_scenes.erase(node)
		exit_replicated_scene.emit(node)
	if node in _visibility_cache:
		_visibility_cache.erase(node)
	node.child_entered_tree.disconnect(_node_child_entered_tree)
	if mp.api and mp.api.repository and mp.api.repository.get_id(node) != -1:
		mp.api.repository.remove_node(node)

func _node_child_entered_tree(node: Node):
	_replicated_scene_search(node)

#endregion

#region Replication Getters

var _visibility_cache := {}

## Returns true if a node is absolutely visible for a peer, false if not.
func get_true_visibility(node: Node, peer: int) -> bool:
	assert(mp.is_server())
	if peer in _visibility_cache.get(node, {}):
		return _visibility_cache[node][peer]
	var visible := true
	var ancestry := _get_replicated_scene_ancestors(node)
	for n in ancestry:
		# Check the visibility settings for the current node.
		var default_visibility: bool = replicated_scenes[n][1]
		var visibility: bool = replicated_scenes[n].get(peer, default_visibility)
		
		# If not visible, then the base node is certainly not visible.
		if not visibility:
			visible = false
			break
	_visibility_cache.get_or_add(node, {})[peer] = visible
	return visible

func _clear_visibility_cache(node: Node, peer := 1):
	if node in _visibility_cache:
		for n in _get_replicated_scene_descendants(node):
			if peer == 1:
				_visibility_cache.erase(n)
			elif peer in _visibility_cache[n]:
				_visibility_cache[n].erase(peer)

## Returns a set of all nodes visible for this peer.
func get_visible_nodes_for_peer(peer: int, root: Node = null) -> Dictionary:
	var dict := {}
	var search := replicated_scenes if not root else _get_replicated_scene_descendants(root)
	for node in search:
		if get_true_visibility(node, peer):
			dict[node] = null
	return dict

## Returns a dict of visible nodes for all peers.
func get_visible_nodes(root: Node = null) -> Dictionary:
	var visible_nodes := {}
	for peer in mp.api.get_peers():
		if peer == 1:
			continue
		visible_nodes[peer] = get_visible_nodes_for_peer(peer, root)
	return visible_nodes

## Return the set of peers who can see this Node.
func get_observing_peers(node: Node) -> Dictionary:
	var peers := {}
	for peer in mp.api.get_peers():
		if peer == 1:
			continue
		if get_true_visibility(node, peer):
			peers[peer] = null
	return peers

func _get_replicated_scene_ancestors(node: Node) -> Dictionary:
	var ancestors := {node: null}
	node = node.get_parent()
	while node != mp:
		if node in replicated_scenes:
			ancestors[node] = null
		node = node.get_parent()
	return ancestors

func _get_replicated_scene_descendants(node: Node) -> Dictionary:
	var descendants := {node: null}
	for n in replicated_scenes:
		if node.is_ancestor_of(n):
			descendants[n] = null
	return descendants

#endregion

#region Visibility

## Sets the networked visibility of a scene.
func set_visibility(node: Node, visibility: bool):
	assert(mp.is_server())
	assert(node.is_node_ready())
	assert(node in replicated_scenes, "Node was not registered as a replicated scene.")
	var old_visibility := get_visible_nodes(node)
	replicated_scenes[node][1] = visibility
	_clear_visibility_cache(node)
	var new_visibility := get_visible_nodes(node)
	_update_nodes(old_visibility, new_visibility)

## Overrides the networked visibility of a scene per peer.
func set_peer_visibility(node: Node, peer: int, visibility: bool):
	assert(mp.is_server())
	assert(node in replicated_scenes, "Node was not registered as a replicated scene.")
	var old_peer_visibility := get_visible_nodes_for_peer(peer, node)
	replicated_scenes[node][peer] = visibility
	_clear_visibility_cache(node, peer)
	var new_peer_visibility := get_visible_nodes_for_peer(peer, node)
	_update_peer_nodes(peer, old_peer_visibility, new_peer_visibility)

## Clears the networked visibility's peer override.
func clear_peer_visibility(node: Node, peer: int):
	assert(mp.is_server())
	assert(node in replicated_scenes, "Node was not registered as a replicated scene.")
	var old_peer_visibility := get_visible_nodes_for_peer(peer, node)
	replicated_scenes[node].erase(peer)
	_clear_visibility_cache(node, peer)
	var new_peer_visibility := get_visible_nodes_for_peer(peer, node)
	_update_peer_nodes(peer, old_peer_visibility, new_peer_visibility)

#endregion

#region Node Ownership

## Sets the owner of a node.
## This is a special peer ID that is replicated across clients.
func set_node_owner(node: Node, peer: int = 1):
	assert(mp.is_server())
	node.set_meta(REPCO.META_OWNER, peer)
	
	# Tell each observing peer who the new owner is.
	if node.is_node_ready():
		assert(node in replicated_scenes)
		var stream := PackedByteStream.new()
		stream.setup_write(4 + mp.api.repository.MAX_BYTES)
		stream.write_unsigned(mp.api.repository.get_id(node), mp.api.repository.MAX_BYTES)
		stream.write_u32(peer)
		for observer in get_observing_peers(node):
			_set_node_owner.rpc_id(observer, stream.data)
		node_owner_updated.emit(node)

## Gets the owner of a node.
func get_node_owner(node: Node) -> int:
	return REPCO.get_node_owner(node)

@rpc
func _set_node_owner(bytes: PackedByteArray):
	var stream := PackedByteStream.new()
	stream.setup_read(bytes)
	var node_id := stream.read_unsigned(mp.api.repository.MAX_BYTES)
	var peer := stream.read_u32()
	var node := mp.api.repository.get_node(node_id)
	if not node_id:
		push_warning("ReplicationService._set_node_owner could not find node ID %s" % node_id)
		return
	node.set_meta(REPCO.META_OWNER, peer)
	node_owner_updated.emit(node)

#endregion

#region Node Operations

## Reparents a replicated scene to a target parent, keeping visibility information persistent.
func reparent_scene(node: Node, parent: Node):
	assert(mp.is_server())
	assert(node in replicated_scenes)
	assert(mp.api.repository.get_id(parent))
	# TODO - Better keep replication information for sub-replicated scenes,
	#        and probably even try to keep the node ID as well
	var visibility_dict: Dictionary = replicated_scenes[node].duplicate()
	var global_visible: bool = visibility_dict[1]
	visibility_dict.erase(1)
	node.get_parent().remove_child(node)
	parent.add_child(node)
	set_visibility(node, global_visible)
	for peer in visibility_dict:
		set_peer_visibility(node, peer, visibility_dict[peer])

#endregion

#region Visibility Internal

func _update_nodes(old_visibility: Dictionary, new_visibility: Dictionary):
	for peer in old_visibility:
		_update_peer_nodes(peer, old_visibility[peer], new_visibility[peer])

func _update_peer_nodes(peer: int, old_peer_visibility: Dictionary, new_peer_visibility: Dictionary):
	# Determine the added and removed nodes.
	var added_nodes: Array[Node] = []
	for now_visible in new_peer_visibility:
		if now_visible not in old_peer_visibility:
			added_nodes.append(now_visible)
	
	var removed_nodes: Array[Node] = []
	for was_visible in old_peer_visibility:
		if was_visible not in new_peer_visibility:
			removed_nodes.append(was_visible)
	
	if not (added_nodes or removed_nodes):
		return
	
	# Pass to RPC serialization.
	_update_visibility(peer, added_nodes, removed_nodes)

var _rpc_added_nodes: Array[Node] = []
var _rpc_removed_nodes: Array[Node] = []

func _update_visibility(peer: int, added_nodes: Array[Node], removed_nodes: Array[Node]):
	if peer not in mp.api.get_peers() or not is_inside_tree():
		return
	# Ensure nodes are inside tree.
	added_nodes.assign(added_nodes.filter(func (n: Node): return n.is_inside_tree()))
	removed_nodes.assign(removed_nodes.filter(func (n: Node): return n.is_inside_tree()))
	
	# Cull removed nodes that are the child of other removed nodes.
	var culled_removed_nodes: Array[Node] = []
	for node in removed_nodes:
		var is_child := false
		var ancestors := _get_replicated_scene_ancestors(node)
		for other in removed_nodes:
			if node == other:
				continue
			if other in ancestors:
				is_child = true
				break
		if is_child:
			break
		culled_removed_nodes.append(node)
	removed_nodes = culled_removed_nodes
	
	# Sort nodepaths by shortest to longest.
	var np_sort_func := func (a: Node, b: Node):
		var a_path := String(a.get_path())
		var b_path := String(b.get_path())
		return len(a_path) < len(b_path)
	if added_nodes:
		added_nodes.sort_custom(np_sort_func)
	if removed_nodes:
		removed_nodes.sort_custom(np_sort_func)
	
	# Determine all of the information we have to replicate.
	var added_node_data := []
	for node in added_nodes:
		var parent_id := mp.api.repository.get_id(node.get_parent())
		if parent_id == -1:
			push_warning("Could not replicate node %s to peer (parent missing repository ID)" % node)
			continue
		var scene_idx := ReplicationCacheManager.get_index(node.scene_file_path)
		if scene_idx == -1:
			push_warning("Could not replicate node %s to peer (scene '%s' is not replicatable)" % [scene_idx, node.scene_file_path])
			continue
		
		var property_values := []
		var node_owner := REPCO.get_node_owner(node)
		
		var replication_data: Dictionary = node.get_meta(REPCO.META_SYNC_PROPERTIES, {})
		for property_path: NodePath in replication_data:
			var property_data: Array = replication_data[property_path]
			match property_data[1]:  # match receive filter
				REPCO.PeerFilter.SERVER:
					continue
				REPCO.PeerFilter.OWNER_SERVER:
					if peer != node_owner:
						continue
				REPCO.PeerFilter.NOT_OWNER:
					if peer == node_owner:
						continue
			var node_path := NodePath(property_path.get_concatenated_names())
			var prop_path := NodePath(property_path.get_concatenated_subnames())
			var target_node := node.get_node(node_path) if node_path else node
			var value := target_node.get_indexed(prop_path)
			property_values.append(value)
		
		var packed_scene: PackedScene = load(node.scene_file_path)
		var scene_state := packed_scene.get_state()
		
		var node_ids := []
		for node_idx in scene_state.get_node_count():
			var node_path := scene_state.get_node_path(node_idx)
			var subnode := node.get_node_or_null(node_path)
			if subnode:
				var subnode_id := mp.api.repository.get_id(subnode)
				node_ids.append(subnode_id if subnode_id != -1 else 0)
			else:
				node_ids.append(0)
		
		var add_data := [
			parent_id,
			node_owner,
			scene_idx,
			property_values,
			node_ids,
		]
		added_node_data.append(add_data)
	
	var removed_node_data: Array[int] = []
	for node in removed_nodes:
		removed_node_data.append(mp.api.repository.get_id(node))
	
	# RPC it.
	var data := _compress_visibility_data(added_node_data, removed_node_data)
	if not data:
		return
	_rpc_added_nodes = added_nodes
	_rpc_removed_nodes = removed_nodes
	update_visibility.rpc_id(peer, data)
	_rpc_added_nodes = []
	_rpc_removed_nodes = []

@rpc
func update_visibility(data: PackedByteArray):
	# Process received visibility data.
	var visibility_data := _decompress_visibility_data(data)
	if not visibility_data:
		return
	
	# Remove nodes.
	var removed_node_data: Array = visibility_data[1]
	for node_id: int in removed_node_data:
		var node := mp.api.repository.get_node(node_id)
		if not node:
			push_warning("Visibility asked to remove node that didn't exist")
			continue
		mp.api.repository.remove_node_id(node_id)
		node.get_parent().remove_child(node)
		node.queue_free()
	
	# Add nodes.
	var added_node_data: Array = visibility_data[0]
	for add_data in added_node_data:
		var parent_id: int = add_data[0]
		var node_owner: int = add_data[1]
		var scene_idx: int = add_data[2]
		var property_values: Array = add_data[3]
		var node_ids: Array = add_data[4]
		
		# Create scene.
		var sfp := ReplicationCacheManager.get_scene_file_path(scene_idx)
		if not sfp:
			push_warning("Received invalid scene path in visibility update.")
			continue
		
		# Find parent.
		var parent := mp.api.repository.get_node(parent_id)
		if not parent:
			push_warning("Received unknown parent node ID %s in visibility update.\nThe server must communicate the replicated scene's parent node ID to the client in advance." % parent_id)
			continue
		
		# Load scene, set properties.
		var packed_scene: PackedScene = load(sfp)
		var scene_state := packed_scene.get_state()
		var scene: Node = packed_scene.instantiate()
		scene.set_meta(REPCO.META_OWNER, node_owner)
		
		# Load owners/IDs first.
		for node_idx in scene_state.get_node_count():
			if node_idx >= node_ids.size():
				push_warning("Received out of bounds node ids on scene.")
				break
			var node_path := scene_state.get_node_path(node_idx)
			var subnode := scene.get_node_or_null(node_path)
			if subnode:
				if subnode != scene and subnode.has_meta(REPCO.META_REPLICATE_SCENE):
					# Delete sub-replicated scenes of the initial scene,
					# replication for them will happen separately.
					subnode.queue_free()
					subnode.get_parent().remove_child(subnode)
				else:
					var node_id: int = node_ids[node_idx]
					if node_id == 0:
						subnode.queue_free()
						subnode.get_parent().remove_child(subnode)
					else:
						mp.api.repository.add_node(subnode, node_id)
			else:
				push_warning("Could not find subnode om received scene. Weird")
				break
		
		# Now load properties.
		var scene_owner := scene.get_meta(REPCO.META_OWNER, 1)
		var replication_data: Dictionary = scene.get_meta(REPCO.META_SYNC_PROPERTIES, {})
		var replication_data_keys := replication_data.keys()
		var true_idx := -1
		for idx: int in replication_data_keys.size():
			var property_path: NodePath = replication_data_keys[idx]
			var property_data: Array = replication_data[property_path]
			match property_data[1]:  # match receive filter
				REPCO.PeerFilter.SERVER:
					continue
				REPCO.PeerFilter.OWNER_SERVER:
					if mp.local_peer != scene_owner:
						continue
				REPCO.PeerFilter.NOT_OWNER:
					if mp.local_peer == scene_owner:
						continue
			true_idx += 1
			
			var prop_node_path := NodePath(property_path.get_concatenated_names())
			var prop_path := NodePath(property_path.get_concatenated_subnames())
			
			var prop_node := scene.get_node_or_null(prop_node_path) if prop_node_path else scene
			if prop_node:
				var value: Variant = property_values[true_idx]
				prop_node.set_indexed(prop_path, value)
		
		# Finally, add scene.
		replicated_scenes[scene] = {}
		enter_replicated_scene.emit(scene)
		parent.add_child(scene)

func _compress_visibility_data(added_node_data: Array, removed_node_data: Array) -> PackedByteArray:
	const MAX_SCENE_BYTES := ReplicationCacheManager.cache_storage.MAX_BYTES
	const MAX_NODE_ID_BYTES := mp.api.repository.MAX_BYTES
	const MAX_NODE_OWNER_BYTES := 4
	
	var stream := PackedByteStream.new()
	stream.setup_write(MAX_NODE_ID_BYTES * 2)
	
	# Encode the number of added/removed nodes.
	var added_node_count := added_node_data.size()
	var removed_node_count := removed_node_data.size()
	stream.write_unsigned(added_node_count, MAX_NODE_ID_BYTES)
	stream.write_unsigned(removed_node_count, MAX_NODE_ID_BYTES)
	
	# Encode added node data.
	for added_data in added_node_data:
		var parent_idx: int = added_data[0]
		var node_owner: int = added_data[1]
		var scene_idx: int = added_data[2]
		var node_properties: Array = added_data[3]
		var node_ids: Array = added_data[4]
		
		assert(scene_idx < (2 ** (MAX_SCENE_BYTES * 8)))
		assert(node_ids.size() < (2 ** (MAX_NODE_ID_BYTES * 8)))
		
		var property_variant := var_to_bytes(node_properties) if not mp.configuration.allow_object_decoding else var_to_bytes_with_objects(node_properties)
		
		stream.allocate(
			MAX_NODE_ID_BYTES
			+ MAX_NODE_OWNER_BYTES
			+ MAX_SCENE_BYTES
			+ property_variant.size()
			+ MAX_NODE_ID_BYTES
			+ (MAX_NODE_ID_BYTES * node_ids.size())
		)
		
		stream.write_unsigned(parent_idx, MAX_NODE_ID_BYTES)
		stream.write_unsigned(node_owner, MAX_NODE_OWNER_BYTES)
		stream.write_unsigned(scene_idx, MAX_SCENE_BYTES)
		stream.write_bytes(property_variant)
		stream.write_unsigned(node_ids.size(), MAX_NODE_ID_BYTES)
		for node_id in node_ids:
			stream.write_unsigned(node_id, MAX_NODE_ID_BYTES)
	
	# Encode removed node data.
	stream.allocate(removed_node_count * MAX_NODE_ID_BYTES)
	for removed_node_id in removed_node_data:
		stream.write_unsigned(removed_node_id, MAX_NODE_ID_BYTES)
	
	# Return.
	if not stream.valid:
		push_error("RPC compression failed in ReplicationService.")
		return PackedByteArray()
	return stream.data

func _decompress_visibility_data(data: PackedByteArray) -> Array:
	const MAX_SCENE_BYTES := ReplicationCacheManager.cache_storage.MAX_BYTES
	const MAX_NODE_ID_BYTES := mp.api.repository.MAX_BYTES
	const MAX_NODE_OWNER_BYTES := 4
	
	var stream := PackedByteStream.new()
	stream.setup_read(data)
	
	# Decode the number of added/removed nodes.
	var added_node_count: int = stream.read_unsigned(MAX_NODE_ID_BYTES)
	var removed_node_count: int = stream.read_unsigned(MAX_NODE_ID_BYTES)
	
	# Decode added node data.
	var added_node_data: Array = []
	for added_data_idx in added_node_count:
		var parent_idx := stream.read_unsigned(MAX_NODE_ID_BYTES)
		var node_owner := stream.read_unsigned(MAX_NODE_OWNER_BYTES)
		var scene_idx := stream.read_unsigned(MAX_SCENE_BYTES)
		var node_properties := stream.read_variant(mp.configuration.allow_object_decoding)
		
		var node_id_count := stream.read_unsigned(MAX_NODE_ID_BYTES)
		var node_ids := []
		for _i in node_id_count:
			node_ids.append(stream.read_unsigned(MAX_NODE_ID_BYTES))
		
		added_node_data.append([parent_idx, node_owner, scene_idx, node_properties, node_ids])
	
	# Decode removed node data.
	var removed_node_data: Array = []
	for _r in removed_node_count:
		removed_node_data.append(stream.read_unsigned(MAX_NODE_ID_BYTES))
	
	# Return.
	if not stream.valid:
		push_warning("RPC decompression failed in ReplicationService.")
		return []
	return [added_node_data, removed_node_data]

#endregion
