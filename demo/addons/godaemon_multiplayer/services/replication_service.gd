extends ServiceBase
class_name ReplicationService
## Tracks the creation of replicated scenes, whose existence can be
## replicated to clients and controlled using visibility.
## This also tracks added nodes for RPCs and replicates their IDs to clients.

const KEY_REPLICATE_CURRENT_SCENE := &"_rcs"

signal node_owner_updated(node: Node)

signal enter_replication(node: Node)
signal exit_replication(node: Node)

## A dictionary map of replicated nodes to their visibility states.
## This contains every replicated script in the multiplayer tree.
var replication_visibility := {}

## A set of replicated nodes (within replication visibility) that should be
## added to their parents before their parents are added to the scenetree.
var dominant_replication := {}

func _enter_tree() -> void:
	# Look for existing replicated scenes, setup initial signals.
	_replication_search(mp)
	if mp.is_server():
		mp.peer_connected.connect(_peer_connected)
		mp.peer_disconnected.connect(_peer_disconnected)
		Godaemon.rpcs(self).target_peer_modifiers.append(_target_peer_modifier)
		Godaemon.rpcs(self).inbound_filters.append(_rpc_filter)

func _peer_connected(peer: int):
	# Peers need to know what initial scenes must be replicated to them.
	var added_nodes: Array[Node] = []
	for node in get_visible_nodes_for_peer(peer):
		if node is MultiplayerRoot or node is ServiceBase:
			continue
		added_nodes.append(node)
	_update_visibility(peer, added_nodes, [])

func _peer_disconnected(peer: int):
	for visibility_dict in replication_visibility.values():
		visibility_dict.erase(peer)
	for visibility_dict in _visibility_cache.values():
		visibility_dict.erase(peer)

#region Service Internals

func _target_peer_modifier(from_peer: int, target_peers: Array[int], node: Node, method: StringName, args: Array):
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
	if from_peer == 1 or to_peer <= 1: return true
	var valid_peers := get_observing_peers(node)
	if from_peer not in valid_peers:
		return false
	if to_peer not in valid_peers:
		return false
	return true

#endregion

#region Replication Setup

# Searches for scenes & replicated scripts.
func _replication_search(node: Node):
	# Only ever scan a node once.
	if node.child_entered_tree.is_connected(_replication_search):
		return
	
	# Setup signal replication for the node.
	# Also emits enter_replication.
	_setup_signal_replication(node)
	
	# Only the server will catalog IDs and replicated scenes,
	# but will tell the client them during replication.
	# The client will still use the exit trees below to cleanup leaving IDs.
	if mp.is_server() and mp.api.repository.get_id(node) == -1:
		mp.api.repository.add_object(node)
		
		if node.scene_file_path and node.has_meta(KEY_REPLICATE_CURRENT_SCENE):
			set_visibility(node, false)
			node.ready.connect(set_visibility.bind(node, true), CONNECT_ONE_SHOT)
	
	# Setup signals on this node.
	node.child_entered_tree.connect(_replication_search)
	node.set_emit_freeing(true)
	node.freeing.connect(_node_tree_exiting.bind(node))
	#node.tree_exiting.connect(_node_tree_exiting.bind(node))
	
	# Continue iteration.
	if node.is_node_ready():
		for child in node.get_children():
			_replication_search(child)

## Recursively registers a node for replication.
## Called when visibility is requested for it.
func _register_replication(node: Node):
	if node in replication_visibility:
		return
	
	if node.scene_file_path:
		# We are registering replication for the root node of a packed scene.
		replication_visibility[node] = {1: false}
	else:
		var script := node.get_script()
		if not script:
			assert(false, "Could not replicate node %s: must be scene or have script" % node)
			return
		replication_visibility[node] = {1: false}

func _node_tree_exiting(node: Node):
	if ReplicationData.get_base_script_replication(node.get_script()):
		exit_replication.emit(node)
	
	if node in dominant_replication:
		dominant_replication.erase(node)
	if node in replication_visibility:
		if mp.api:
			for peer in get_observing_peers(node):
				_update_visibility(peer, [], [node])
		replication_visibility.erase(node)
	
	if node in _visibility_cache:
		_visibility_cache.erase(node)
	if mp and mp.api and mp.api.repository and mp.api.repository.get_id(node) != -1:
		mp.api.repository.remove_object(node)

#endregion

#region Reparenting

## Replicates a node reparent to clients.
func reparent_node(node: Node, parent: Node):
	if node in replication_visibility:
		_clear_visibility_cache(node)
	var node_id := mp.api.repository.get_id(node)
	var parent_id := mp.api.repository.get_id(parent)
	__node_reparent.rpc(node_id, parent_id)

## Internal node reparent replication
@rpc
func __node_reparent(node_id: int, parent_id: int):
	var node: Node = mp.api.repository.get_object(node_id)
	var parent: Node = mp.api.repository.get_object(parent_id)
	if not node:
		return
	elif node.get_parent() == parent:
		# No reparenting has occurred
		return
	elif node and not parent:
		# Node reparented to node we don't know, effectively cleanup
		node.get_parent().remove_child(node)
		node.queue_free()
	elif node and parent:
		# Node reparented to node we do know, replicate the reparent
		node.reparent(parent)

#endregion

#region Replication Getters

var _visibility_cache := {}

## Returns true if a node is absolutely visible for a peer, false if not.
func get_true_visibility(node: Node, peer: int) -> bool:
	assert(mp.is_server())
	if node is MultiplayerRoot or node is ServiceBase:
		return true
	if peer in _visibility_cache.get(node, {}):
		return _visibility_cache[node][peer]
	var visible := true
	var ancestry := _get_replicated_ancestors(node)
	for n in ancestry:
		# Check the visibility settings for the current node.
		var default_visibility: bool = replication_visibility[n][1]
		var visibility: bool = replication_visibility[n].get(peer, default_visibility)
		
		# If not visible, then the base node is certainly not visible.
		if not visibility:
			visible = false
			break
	_visibility_cache.get_or_add(node, {})[peer] = visible
	return visible

func _clear_visibility_cache(node: Node, peer := 1):
	if node in _visibility_cache:
		for n in _get_replicated_descendants(node, true):
			if peer == 1:
				_visibility_cache.erase(n)
			elif peer in _visibility_cache[n]:
				_visibility_cache[n].erase(peer)

## Returns a set of all nodes visible for this peer.
func get_visible_nodes_for_peer(peer: int, root: Node = null) -> Dictionary:
	var dict := {}
	var search := replication_visibility if not root else _get_replicated_descendants(root)
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
	if node in _client_created_scenes:
		peers[_client_created_scenes[node]] = null
	return peers

func _get_replicated_ancestors(node: Node) -> Dictionary:
	var ancestors := {}
	while node != mp and node:
		if node in replication_visibility:
			ancestors[node] = null
		node = node.get_parent()
	return ancestors

func _get_replicated_descendants(node: Node, include_cache := false) -> Dictionary:
	var descendants := {}
	if node in replication_visibility:
		descendants[node] = null
	for n in replication_visibility:
		if not is_instance_valid(n):
			continue
		if node.is_ancestor_of(n):
			descendants[n] = null
	if include_cache:
		for n in _visibility_cache:
			if not is_instance_valid(n):
				continue
			if n in descendants:
				continue
			if node.is_ancestor_of(n):
				descendants[n] = null
	return descendants

#endregion

#region Signal Replication

## Sets up signal replication for a node. Called on server and client.
func _setup_signal_replication(node: Node):
	# Setup initial replication.
	var base_sr := ReplicationData.get_base_script_replication(node.get_script())
	if not base_sr:
		return
	
	if mp.is_server():
		# If this node's parent is not ready, then the parent is still being added to the tree.
		# Therefore, we need to give it priority later during client replication.
		if node.owner and not node.owner.is_node_ready():
			#print(node.owner.get_path())
			dominant_replication[node] = null
	
	enter_replication.emit(node)  # kinda lazily merged into here, but fast
	
	# Now setup signal replication.
	for sr in ReplicationData.get_all_script_replications(node.get_script()):
		for c in sr.signal_config:
			if c.can_we_send(mp, node):
				node.connect(
					StringName(c.name),
					func (
						arg1: Variant = null, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null,
						arg5: Variant = null, arg6: Variant = null, arg7: Variant = null, arg8: Variant = null
						):
						_on_signal_emit(
							arg1, arg2, arg3, arg4,
							arg5, arg6, arg7, arg8,
							node, base_sr, c
						)
				)

var _signal_loop_block := {}

func _on_signal_emit(
		arg1: Variant = null, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null,
		arg5: Variant = null, arg6: Variant = null, arg7: Variant = null, arg8: Variant = null,
		node: Node = null, sr: ScriptReplication = null, c: ReplicationSignalConfig = null
		):
	if _is_signal_loop_blocked(node, c):
		return
	
	var args: Array = []
	if c.arg_count >= 1: args.append(arg1)
	if c.arg_count >= 2: args.append(arg2)
	if c.arg_count >= 3: args.append(arg3)
	if c.arg_count >= 4: args.append(arg4)
	if c.arg_count >= 5: args.append(arg5)
	if c.arg_count >= 6: args.append(arg6)
	if c.arg_count >= 7: args.append(arg7)
	if c.arg_count >= 8: args.append(arg8)
	if c.arg_count >= 9: assert(false, "Replicated signal max argument reached")
	
	var idx := ReplicationData.object_signal_to_idx(node, c)
	if idx == -1:
		assert(false)
		return
	await mp.api.repository.await_for_id(get_tree(), node)
	var node_id := mp.api.repository.get_id(node)
	for p in get_observing_peers(node):
		if c.can_they_recv(node, p):
			if c.reliable:
				_signal_replicate_reliable.rpc_id(p, node_id, idx, args)
			else:
				_signal_replicate_unreliable.rpc_id(p, node_id, idx, args)

@rpc
func _signal_replicate_reliable(node_id: int, idx: int, args: Array):
	_signal_replicate(node_id, idx, args)

@rpc
func _signal_replicate_unreliable(node_id: int, idx: int, args: Array):
	_signal_replicate(node_id, idx, args)

func _signal_replicate(node_id: int, idx: int, args: Array):
	var node := mp.api.repository.get_object(node_id)
	if not node:
		return
	var c := ReplicationData.object_idx_to_signal(node, idx)
	if not c.can_we_recv(mp, node):
		return
	_set_signal_loop_block(node, c, true)
	match args.size():
		0: node.emit_signal(c.name)
		1: node.emit_signal(c.name, args[0])
		2: node.emit_signal(c.name, args[0], args[1])
		3: node.emit_signal(c.name, args[0], args[1], args[2])
		4: node.emit_signal(c.name, args[0], args[1], args[2], args[3])
		5: node.emit_signal(c.name, args[0], args[1], args[2], args[3], args[4])
		6: node.emit_signal(c.name, args[0], args[1], args[2], args[3], args[4], args[5])
		7: node.emit_signal(c.name, args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		8: node.emit_signal(c.name, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])
		9: assert(false)
	_set_signal_loop_block(node, c, false)

func _set_signal_loop_block(node: Node, c: ReplicationSignalConfig, block: bool):
	if block:
		if node not in _signal_loop_block:
			_signal_loop_block[node] = {}
		if c not in _signal_loop_block[node]:
			_signal_loop_block[node][c] = 0
		_signal_loop_block[node][c] += 1
	else:
		if node in _signal_loop_block:
			if c in _signal_loop_block[node]:
				_signal_loop_block[node][c] -= 1
				if _signal_loop_block[node][c] <= 0:
					_signal_loop_block[node].erase(c)
					if not _signal_loop_block[node]:
						_signal_loop_block.erase(node)

func _is_signal_loop_blocked(node: Node, c: ReplicationSignalConfig) -> bool:
	if node in _signal_loop_block:
		if c in _signal_loop_block[node]:
			return true
	return false

#endregion

#region Client Replicated Scene

## Client replicated scenes take an interesting flow:
## 1. Client calls ReplicationService.request_replication(node).
## 2. The server will emit ReplicationService.replication_request_validation. Something must validate and call the callable.
## 3. If valid, the server will replicate the node to other peers, and assign node IDs back to the calling client.

## Emitted on the server when a replication request is made on a client.
signal replication_request_validation(parent: Node, res: Resource, peer: int, cb: Callable)

var client_queued_replication_tokens: Dictionary[int, Node] = {}
var client_replication_token_idx := 0

var _client_created_scenes: Dictionary[Node, int] = {}

## A client can call this function to request a local script/scene to become replicated.
## Note that the server must listen & emit the above signal to accept the request.
func request_replication(node: Node):
	if not mp.is_client():
		assert(false, "cannot request replication on client")
		return
	if not node.is_inside_tree():
		assert(false, "replicated node must be inside tree")
		return
	var parent := node.get_parent()
	await mp.api.repository.await_for_id(get_tree(), parent)
	var parent_id := mp.api.repository.get_id(parent)
	if parent_id == -1:
		assert(false, "replication parent must have ID")
		return
	var args := ReplicationData.get_object_property_values(node)
	var token_idx := client_replication_token_idx
	client_queued_replication_tokens[token_idx] = node
	client_replication_token_idx += 1
	mp.api.repository.add_object_id_await(node)
	if node.scene_file_path:
		var uid := path_to_uid(node.scene_file_path)
		_request_replication.rpc(parent_id, uid, args, token_idx)
	elif node.get_script():
		var uid := path_to_uid(node.get_script().resource_path)
		_request_replication.rpc(parent_id, uid, args, token_idx)
	else:
		assert(false, "unknown replication uid")

@rpc
func _request_replication(parent_id: int, uid: int, args: Array, token: int):
	# Server receives this to forward attack replication to other clients.
	var parent := mp.api.repository.get_object(parent_id)
	if not parent:
		return
	var path := uid_to_path(uid)
	if not path:
		return
	var res := load(path)
	if res is not Script and res is not PackedScene:
		return
	replication_request_validation.emit(parent, res, mp.remote_peer, _accept_replication.bind(parent, res, mp.remote_peer, args, token))

func _accept_replication(parent: Node, res: Resource, peer: int, args: Array, token: int):
	var n: Node = null
	if res is Script:
		n = res.new()
	elif res is PackedScene:
		n = res.instantiate()
	else:
		assert(false)
		return
	#_forced_visibility[n] = true
	_client_created_scenes[n] = peer
	set_peer_visibility(n, peer, false)
	set_visibility(n, true)
	ReplicationData.apply_object_property_values(mp, n, args, 0)
	parent.add_child(n)
	var node_id := mp.api.repository.get_id(n)
	_receive_client_replication_ids.rpc_id(peer, token, node_id)

@rpc
func _receive_client_replication_ids(token: int, node_id: int):
	if token not in client_queued_replication_tokens:
		return
	var node := client_queued_replication_tokens[token]
	client_queued_replication_tokens.erase(token)
	if node and is_instance_valid(node) and not node.is_queued_for_deletion():
		mp.api.repository.add_object(node, node_id)

#endregion

#region Client Scene Remap

var _client_scene_remaps: Dictionary[PackedScene, PackedScene] = {}
var _client_script_remaps: Dictionary[Script, Script] = {}

## Tells the ReplicationService to transform a received scene into
## another one, who must be identical in structure.
func remap_scene(from_scene: PackedScene, into_scene: PackedScene):
	assert(mp.is_client())
	_client_scene_remaps[from_scene] = into_scene

## Tells the ReplicationService to transform a received script into another.
func remap_script(from_script: Script, to_script: Script):
	assert(mp.is_client())
	_client_script_remaps[from_script] = to_script

#endregion

#region Visibility

## Registers a node to set its visibility upon entering the tree.
## Allows it to have default visibility before ready.
func register_enter_visibility(node: Node, visibility := false):
	assert(mp.is_server())
	assert(not node.is_inside_tree())
	var f := set_visibility.bind(node, visibility)
	if not node.tree_entered.is_connected(f):
		node.tree_entered.connect(f, CONNECT_ONE_SHOT)

## Sets the networked visibility of a replicated script.
func set_visibility(node: Node, visibility: bool):
	assert(mp.is_server())
	if not node.is_inside_tree():
		register_enter_visibility(node, false)
		node.ready.connect(set_visibility.bind(node, visibility), CONNECT_ONE_SHOT)
		return
	_register_replication(node)
	var old_visibility := get_visible_nodes(node)
	replication_visibility[node][1] = visibility
	_clear_visibility_cache(node)
	var new_visibility := get_visible_nodes(node)
	_update_nodes(old_visibility, new_visibility)

## Overrides the networked visibility of a scene per peer.
func set_peer_visibility(node: Node, peer: int, visibility: bool):
	assert(mp.is_server())
	if not node.is_inside_tree():
		register_enter_visibility(node, false)
		node.ready.connect(set_peer_visibility.bind(node, peer, visibility), CONNECT_ONE_SHOT)
		return
	_register_replication(node)
	var old_peer_visibility := get_visible_nodes_for_peer(peer, node)
	replication_visibility[node][peer] = visibility
	_clear_visibility_cache(node, peer)
	var new_peer_visibility := get_visible_nodes_for_peer(peer, node)
	_update_peer_nodes(peer, old_peer_visibility, new_peer_visibility)

## Clears the networked visibility's peer override.
func clear_peer_visibility(node: Node, peer: int):
	assert(mp.is_server())
	assert(node.is_inside_tree())
	_register_replication(node)
	var old_peer_visibility := get_visible_nodes_for_peer(peer, node)
	replication_visibility[node].erase(peer)
	_clear_visibility_cache(node, peer)
	var new_peer_visibility := get_visible_nodes_for_peer(peer, node)
	_update_peer_nodes(peer, old_peer_visibility, new_peer_visibility)

#endregion

#region Node Ownership

## Sets the owner of a node.
## This is a special peer ID that is replicated across clients.
func set_node_owner(node: Node, peer: int = 1):
	assert(mp.is_server())
	node.set_meta(Godaemon.META_OWNER, peer)
	
	# Tell each observing peer who the new owner is.
	if node.is_node_ready():
		assert(node in replication_visibility)
		var stream := PackedByteStream.new()
		stream.setup_write(4 + mp.api.repository.MAX_BYTES)
		stream.write_unsigned(mp.api.repository.get_id(node), mp.api.repository.MAX_BYTES)
		stream.write_u32(peer)
		for observer in get_observing_peers(node):
			_set_node_owner.rpc_id(observer, stream.data)
		node_owner_updated.emit(node)

@rpc
func _set_node_owner(bytes: PackedByteArray):
	var stream := PackedByteStream.new()
	stream.setup_read(bytes)
	var node_id := stream.read_unsigned(mp.api.repository.MAX_BYTES)
	var peer := stream.read_u32()
	var node := mp.api.repository.get_object(node_id)
	if not node_id:
		push_warning("ReplicationService._set_node_owner could not find node ID %s" % node_id)
		return
	node.set_meta(Godaemon.META_OWNER, peer)
	node_owner_updated.emit(node)

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

func np_sort_ascending(a: Node, b: Node):
	return mp.api.repository.get_id(a) < mp.api.repository.get_id(b)

func np_sort_descending(a: Node, b: Node):
	return mp.api.repository.get_id(a) > mp.api.repository.get_id(b)

func _update_visibility(peer: int, added_nodes: Array[Node], removed_nodes: Array[Node]):
	if peer not in mp.api.get_peers() or not is_inside_tree():
		return
	
	# Ensure added nodes are inside tree.
	#for idx in range(added_nodes.size() - 1, -1, -1):
		#if not added_nodes[idx].is_inside_tree():
			#added_nodes.pop_at(idx)
	
	# Cull removed nodes that are the child of other removed nodes.
	#var culled_removed_nodes: Array[Node] = []
	#for node in removed_nodes:
		#var is_child := false
		#var ancestors := _get_replicated_ancestors(node)
		#for other in removed_nodes:
			#if node == other:
				#continue
			#if other in ancestors:
				#is_child = true
				#break
		#if is_child:
			#break
		#culled_removed_nodes.append(node)
	#removed_nodes = culled_removed_nodes
	
	if added_nodes:
		# smallest to largest for added nodes, so early nodes are added first
		added_nodes.sort_custom(np_sort_ascending)
	if removed_nodes:
		# smallest to largest for removed nodes, so early nodes are removed first
		removed_nodes.sort_custom(np_sort_ascending)
	
	# Determine all of the information we have to replicate.
	var added_node_data := []
	for node in added_nodes:
		var parent_id := mp.api.repository.get_id(node.get_parent())
		if parent_id == -1:
			push_warning("Could not replicate node %s to peer (parent missing repository ID).\nEnsure the parent is in a replicated scene." % node)
			continue
		
		# Embed data differently depending on if its a scene or not.
		var dominant := node in dominant_replication
		if not node.scene_file_path:
			# The node is not a scene -- it is just an individual script.
			# Get all of its information.
			var node_id: int = mp.api.repository.get_id(node)
			
			# Add the data for this script.
			var add_data := [
				parent_id,
				Godaemon.get_node_owner(node),
				path_to_uid(node.get_script().resource_path),
				{node_id: ReplicationData.get_object_property_values(node, peer)},
				[node_id],
				dominant,
			]
			added_node_data.append(add_data)
		else:
			# Scene replication will demand that we traverse the entire scene,
			# determining which properties to replicate along the way.
			# Grab all scene states.
			var packed_scene: PackedScene = load(node.scene_file_path)
			var scene_states: Array[SceneState] = []
			while true:
				var scene_state := packed_scene.get_state()
				scene_states.append(scene_state)
				packed_scene = scene_state.get_node_instance(0)
				if not packed_scene: break
			
			# Traverse all scene states.
			var property_values := {}
			var node_ids := []
			for scene_state in scene_states:
				for node_idx in scene_state.get_node_count():
					# Get the subnode at this part of the scene state.
					var node_path := scene_state.get_node_path(node_idx)
					var subnode := node.get_node_or_null(node_path)
					
					# If the subnode exists AND has no associated visibility control,
					# we can replicate it here. Otherwise, its replication occurs separately.
					if subnode and (subnode not in replication_visibility or node == subnode):
						var subnode_id := mp.api.repository.get_id(subnode)
						if subnode_id != -1:
							# Catalog this node's ID here.
							node_ids.append(subnode_id)
							
							# Also, determine the node's property values for replication here.
							var node_property_values := ReplicationData.get_object_property_values(subnode, peer)
							if node_property_values:
								property_values[subnode_id] = node_property_values
						else:
							# We tried replicating a node without a node id -- what?
							# This should never happen.
							assert(false)
							node_ids.append(0)
					else:
						# The node was not present here, so we flag it as 0
						# so it's non-existent to the client.
						node_ids.append(0)
			
			var add_data := [
				parent_id,
				Godaemon.get_node_owner(node),
				path_to_uid(node.scene_file_path),
				property_values,
				node_ids,
				dominant,
			]
			added_node_data.append(add_data)
	
	var removed_node_data: Array[int] = []
	for node in removed_nodes:
		removed_node_data.append(mp.api.repository.get_id(node))
	
	# RPC it.
	var data := _compress_visibility_data(added_node_data, removed_node_data)
	if not data:
		return
	#Log.info(self, "Sending visibility:\n\tadding %s\n\tremoving %s" % [added_nodes, removed_nodes])
	_rpc_added_nodes = added_nodes
	_rpc_removed_nodes = removed_nodes
	update_visibility.rpc_id(peer, data)
	_rpc_added_nodes = []
	_rpc_removed_nodes = []

@rpc
func update_visibility(data: PackedByteArray):
	# Process received visibility data.
	#Log.start_benchmark(self, "visibility: decompress")
	var visibility_data := _decompress_visibility_data(data)
	#Log.end_benchmark(self)
	if not visibility_data:
		return
	
	# Remove nodes.
	#Log.start_benchmark(self, "visibility: remove nodes")
	var removed_node_data: Array = visibility_data[1]
	for node_id: int in removed_node_data:
		var node: Node = mp.api.repository.get_object(node_id)
		if not node:
			push_warning("Visibility asked to remove node that didn't exist")
			continue
		elif not node.is_inside_tree():
			continue
		#mp.api.repository.remove_object_id(node_id)
		node.get_parent().remove_child(node)
		node.queue_free()
	#Log.end_benchmark(self)
	
	# Iterate over all added nodes, and start building their node heirarchy.
	var added_node_data: Array = visibility_data[0]
	var ids_to_lodes: Dictionary[int, Node] = {}
	var dominant_lode_ids: Array[int] = []
	var lode_id_to_parent_ids: Dictionary[int, int] = {}
	for add_data in added_node_data:
		var parent_id: int = add_data[0]
		var node_owner: int = add_data[1]
		var node_uid: int = add_data[2]
		var property_values: Dictionary = add_data[3]
		var node_ids: Array = add_data[4]
		var dominant: bool = add_data[5]
		
		# Get resource path.
		var resource_path := uid_to_path(node_uid)
		if not resource_path:
			push_warning("Received invalid resource path in visibility update.")
			continue
		
		# Load resource path.
		#Log.start_benchmark(self, "visibility: heirarchy build (load %s)" % resource_path)
		var resource: Resource = load(resource_path)
		#Log.end_benchmark(self)
		#Log.start_benchmark(self, "visibility: heirarchy build (prep %s)" % resource_path)
		if resource is Script:
			# Create script, set properties.
			var script: Script = resource
			script = _client_script_remaps.get(script, script)
			
			var node: Node = script.new()
			node.set_meta(Godaemon.META_OWNER, node_owner)
			mp.api.repository.add_object(node, node_ids[0])
			
			# Load the root node's script replication.
			if property_values:
				ReplicationData.apply_object_property_values(mp, node, property_values[node_ids[0]])
			
			# Setup build cache.
			var node_id: int = node_ids[0]
			ids_to_lodes[node_id] = node
			lode_id_to_parent_ids[node_id] = parent_id
			if dominant:
				dominant_lode_ids.append(node_id)
			
		elif resource is PackedScene:
			# Load scene, set properties.
			var packed_scene: PackedScene = resource
			packed_scene = _client_scene_remaps.get(packed_scene, packed_scene)
			var root_packed_scene := packed_scene
			
			var scene: Node = packed_scene.instantiate()
			scene.set_meta(Godaemon.META_OWNER, node_owner)
			
			# todo remove
			#var dev := false
			#if scene is DungeonBossBase:
				#dev = true
				#breakpoint
			
			var scene_states: Array[SceneState] = []
			while true:
				var scene_state := packed_scene.get_state()
				scene_states.append(scene_state)
				packed_scene = scene_state.get_node_instance(0)
				if not packed_scene: break
			
			var existing_paths: Dictionary[NodePath, Node] = {}
			var dead_paths: Dictionary[NodePath, Node] = {}
			
			# Load all replication and IDs.
			var node_ids_idx := -1
			for scene_state in scene_states:
				for node_idx in scene_state.get_node_count():
					node_ids_idx += 1
					if node_idx >= node_ids.size():
						push_warning("Received out of bounds node ids on scene.")
						continue
					var node_path := scene_state.get_node_path(node_idx)
					var subnode := scene.get_node_or_null(node_path)
					if subnode:
						
						#if subnode is Sigil and dev:
							#breakpoint
						#if subnode is Waypoint3D and dev:
							#breakpoint
						
						if OS.has_feature("debug"):
							for dp in dead_paths:
								if is_node_path_ancestor(dp, node_path):
									push_error("Node %s from scene %s is being deleted mid-replication.\nThis is due to its ancestor being deleted/recreated during replication (likely its ancestor is a scene or replicated script).\nThis node must be moved elsewhere in the heirarchy, or added to its replicated scene." % [node_path, root_packed_scene.resource_path.get_file()])
						
						var node_id: int = node_ids[node_ids_idx]
						if node_id != 0:
							# This node is being added to the tree.
							# Register its node ID now.
							existing_paths[node_path] = subnode
							if mp.api.repository.get_object(node_id) != subnode:
								mp.api.repository.add_object(subnode, node_id)
							
							# Set this node's properties.
							if node_id in property_values:
								ReplicationData.apply_object_property_values(mp, subnode, property_values[node_id])
						else:
							# Flag this nodepath as being dead.
							dead_paths[node_path] = subnode
					else:
						#push_warning("Could not find subnode %s on received scene %s. Weird" % [node_path, packed_scene.resource_path])
						continue
			
			# Kill each nodepath we could not find a reference for.
			for np in dead_paths:
				if np in existing_paths: continue  # this node was created actually, likely by a child PackedScene
				var sn: Node = dead_paths[np]
				sn.queue_free()
				sn.get_parent().remove_child(sn)
			
			# Setup build cache.
			var node_id: int = node_ids[0]
			ids_to_lodes[node_id] = scene
			lode_id_to_parent_ids[node_id] = parent_id
			if dominant:
				dominant_lode_ids.append(node_id)
		else:
			push_warning("Received invalid UID in visibility update (%s neither script nor scene)" % resource_path)
			continue
		#Log.end_benchmark(self)
	
	#Log.start_benchmark(self, "visibility: lode sorting")
	
	# Determine the lode ID processing order.
	var lode_id_order: Array[int] = []
	for lode_id in dominant_lode_ids:  # pass 1: dominant first
		#Log.info(self, "%s: dominant" % get_readable_node_name(ids_to_lodes[lode_id]))
		lode_id_order.append(lode_id)
	for lode_id in ids_to_lodes:  # pass 2: all non-dominant
		if lode_id in dominant_lode_ids:
			continue
		#Log.info(self, "%s: recessive" % get_readable_node_name(ids_to_lodes[lode_id]))
		lode_id_order.append(lode_id)
	
	# Build the lode addition order.
	var lode_order: Dictionary[Node, Node] = {}
	for lode_id: int in lode_id_order:
		var lode := ids_to_lodes[lode_id]
		var parent_id := lode_id_to_parent_ids[lode_id]
		if parent_id in ids_to_lodes:
			var parent_lode := ids_to_lodes[parent_id]
			lode_order[lode] = parent_lode
		else:
			var parent_node := _try_get_parent(parent_id)
			if parent_node:
				lode_order[lode] = parent_node
			else:
				lode.queue_free()
	
	#Log.end_benchmark(self)
	#Log.start_benchmark(self, "visibility: lode into tree")
	
	# Now add all lodes.
	for lode in lode_order:
		replication_visibility[lode] = {}
		
		# debug
		#if true:
			#var parent := lode_order[lode]
			#Log.info(self, "%s: adding child %s" % [get_readable_node_name(parent), get_readable_node_name(lode)])
		
		lode_order[lode].add_child(lode)
	
	#Log.end_benchmark(self)
	#print()

func _try_get_parent(parent_id: int) -> Node:
	var parent := mp.api.repository.get_object(parent_id)
	if not parent:
		push_warning("Received unknown parent node ID %s in visibility update.
		This is likely caused by an ancestor scene being added to the server and not having its visibility configured properly." % parent_id)
		if OS.has_feature("editor"):
			_ask_missing_id.rpc(parent_id)
		return null
	return parent

static func get_readable_node_name(n: Node) -> String:
	if n.scene_file_path:
		return n.scene_file_path.get_file()
	if n.get_script():
		return n.get_script().resource_path.get_file()
	return n.name

func _compress_visibility_data(added_node_data: Array, removed_node_data: Array) -> PackedByteArray:
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
		var node_uid: int = added_data[2]
		var node_properties: Dictionary = added_data[3]
		var node_ids: Array = added_data[4]
		var dominant: bool = added_data[5]
		
		assert(node_ids.size() < (2 ** (MAX_NODE_ID_BYTES * 8)))
		
		var property_variant := var_to_bytes(node_properties)
		
		stream.allocate(
			MAX_NODE_ID_BYTES
			+ MAX_NODE_OWNER_BYTES
			+ 8
			+ property_variant.size()
			+ MAX_NODE_ID_BYTES
			+ (MAX_NODE_ID_BYTES * node_ids.size())
			+ 1
		)
		
		stream.write_unsigned(parent_idx, MAX_NODE_ID_BYTES)
		stream.write_unsigned(node_owner, MAX_NODE_OWNER_BYTES)
		stream.write_unsigned(node_uid, 8)
		stream.write_bytes(property_variant)
		stream.write_unsigned(node_ids.size(), MAX_NODE_ID_BYTES)
		for node_id in node_ids:
			stream.write_unsigned(node_id, MAX_NODE_ID_BYTES)
		stream.write_u8(int(dominant))
	
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
		var parent_idx: int = stream.read_unsigned(MAX_NODE_ID_BYTES)
		var node_owner: int = stream.read_unsigned(MAX_NODE_OWNER_BYTES)
		var node_uid: int = stream.read_unsigned(8)
		var node_properties: Dictionary = stream.read_variant(false)
		
		var node_id_count := stream.read_unsigned(MAX_NODE_ID_BYTES)
		var node_ids := []
		for _i in node_id_count:
			node_ids.append(stream.read_unsigned(MAX_NODE_ID_BYTES))
		
		var dominant: bool = bool(stream.read_u8())
		
		added_node_data.append([parent_idx, node_owner, node_uid, node_properties, node_ids, dominant])
	
	# Decode removed node data.
	var removed_node_data: Array = []
	for _r in removed_node_count:
		removed_node_data.append(stream.read_unsigned(MAX_NODE_ID_BYTES))
	
	# Return.
	if not stream.valid:
		push_warning("RPC decompression failed in ReplicationService.")
		return []
	return [added_node_data, removed_node_data]

@rpc
func _ask_missing_id(node_id: int):
	if OS.has_feature("editor"):
		var n := mp.api.repository.get_object(node_id)
		push_warning("peer %s missing id %s: %s" % [mp.remote_peer, node_id, mp.get_path_to(n) if n else "unknown NP!"])

#endregion

#region Static util

# Apparently, these functions seem expensive, so I'm adding caches for them.
static var _uid_to_path_cache: Dictionary[int, String] = {}
static var _path_to_uid_cache: Dictionary[String, int] = {}

## converts uid => path (returns "" if doesnt exist)
static func uid_to_path(uid: int) -> String:
	if uid in _uid_to_path_cache:
		return _uid_to_path_cache[uid]
	var path := ""
	if ResourceUID.has_id(uid):
		path = ResourceUID.get_id_path(uid)
	_uid_to_path_cache[uid] = path
	return path

## converts path => uid (returns -1 if doesnt exist)
static func path_to_uid(path: String) -> int:
	if path in _path_to_uid_cache:
		return _path_to_uid_cache[path]
	var uid := ResourceLoader.get_resource_uid(path)
	_path_to_uid_cache[path] = uid
	return uid

static func is_node_path_ancestor(parent_np: NodePath, np: NodePath) -> bool:
	if parent_np == np:
		return false
	while np:
		if parent_np == np:
			return true
		np = np.slice(0, -1)
	return false

#endregion
