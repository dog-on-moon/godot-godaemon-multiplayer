extends SubViewport
class_name Zone
## A Zone is the root node of all distributed scenes in the godaemon_multiplayer API.
## After a ServerRoot adds a scene, it lives within a Zone.
## The contents can then be automatically replicated to clients
## by assigning peer visibility.

#region Signals

## Emitted when a peer has gained interest with this Zone.
signal interest_added(peer: int)

## Emitted when a peer has lost interest with this Zone.
signal interest_removed(peer: int)

#endregion

#region Exports

## The World2D used to encapsulate this Zone's canvas, physics, and navigation.
## This keeps physics and navigation exclusive to this Zone.
## It can be overridden to share a World2D with another Zone.
@export var _world_2d := World2D.new():
	set(x):
		if x == null:
			x = World2D.new()
		_world_2d = x
		if not Engine.is_editor_hint():
			world_2d = x

## The World3D used to encapsulate this Zone's camera, environment, physics, and navigation.
## This keeps physics and navigation exclusive to this Zone.
## It can be overridden to share a World3D with another Zone.
@export var _world_3d := World3D.new():
	set(x):
		if x == null:
			x = World3D.new()
		_world_3d = x
		if not Engine.is_editor_hint():
			world_3d = x

## When true, the Zone will use the game window's rendering settings.
## Leave this true unless you want to customize the viewport's rendering settings.
## Please call `ZoneService.update_render_properties()` whenever you update the game
## window's rendering settings, so that the Zones will update as well.
var use_window_render_settings := true

#endregion

#region Properties

#set by ZoneService
var mp: MultiplayerRoot
var zone_service: ZoneService

## A dictionary mapping peers to null.
var interest := {}

## The scene we're in charge of.
var scene: Node

#endregion

#region Rendering

@onready var __setup_rendering := _setup_rendering.call()
func _setup_rendering():
	# Set default rendering parameters of the Viewport.
	render_target_clear_mode = CLEAR_MODE_ALWAYS
	render_target_update_mode = UPDATE_ALWAYS if mp.is_client() else UPDATE_WHEN_VISIBLE
	transparent_bg = true
	handle_input_locally = false
	
	if not Engine.is_editor_hint():
		# Copy properties from the window viewport.
		update_render_properties(get_parent().get_viewport())

## Copies the viewport rendering mode from a window.
## If 'use_window_render_settings' is set, this will automatically
## capture parameters from the game window.
func update_render_properties(viewport: Viewport):
	if not use_window_render_settings:
		return
	snap_2d_transforms_to_pixel = viewport.snap_2d_transforms_to_pixel
	snap_2d_vertices_to_pixel = viewport.snap_2d_vertices_to_pixel
	msaa_2d = viewport.msaa_2d
	msaa_3d = viewport.msaa_3d
	screen_space_aa = viewport.screen_space_aa
	use_taa = viewport.use_taa
	use_debanding = viewport.use_debanding
	use_occlusion_culling = viewport.use_occlusion_culling
	mesh_lod_threshold = viewport.mesh_lod_threshold
	debug_draw = viewport.debug_draw
	use_hdr_2d = viewport.use_hdr_2d
	scaling_3d_mode = viewport.scaling_3d_mode
	scaling_3d_scale = viewport.scaling_3d_scale
	texture_mipmap_bias = viewport.texture_mipmap_bias
	fsr_sharpness = viewport.fsr_sharpness
	vrs_mode = viewport.vrs_mode
	vrs_update_mode = viewport.vrs_update_mode
	vrs_texture = viewport.vrs_texture
	canvas_item_default_texture_filter = viewport.canvas_item_default_texture_filter
	canvas_item_default_texture_repeat = viewport.canvas_item_default_texture_repeat
	audio_listener_enable_2d = viewport.audio_listener_enable_2d
	audio_listener_enable_3d = viewport.audio_listener_enable_3d
	physics_object_picking = viewport.physics_object_picking
	physics_object_picking_sort = viewport.physics_object_picking_sort
	physics_object_picking_first_only = viewport.physics_object_picking_first_only
	gui_disable_input = viewport.gui_disable_input
	gui_snap_controls_to_pixels = viewport.gui_snap_controls_to_pixels
	gui_embed_subwindows = viewport.gui_embed_subwindows
	sdf_oversize = viewport.sdf_oversize
	sdf_scale = viewport.sdf_scale
	positional_shadow_atlas_size = viewport.positional_shadow_atlas_size
	positional_shadow_atlas_16_bits = viewport.positional_shadow_atlas_16_bits
	positional_shadow_atlas_quad_0 = viewport.positional_shadow_atlas_quad_0
	positional_shadow_atlas_quad_1 = viewport.positional_shadow_atlas_quad_1
	positional_shadow_atlas_quad_2 = viewport.positional_shadow_atlas_quad_2
	positional_shadow_atlas_quad_3 = viewport.positional_shadow_atlas_quad_3

#endregion

#region Replication

const REPCO = preload("res://addons/godaemon_multiplayer/services/replication/replication_constants.gd")

## Server-sided set of all nodes with some kind of replication state.
var replication_nodes := {}

@onready var __setup_replication := _setup_replication.call()
func _setup_replication():
	if not mp.is_server():
		return
	
	# Perform an initial search of the scene.
	_node_enter_zone(scene, replication_nodes)

func _node_enter_zone(root: Node, data: Dictionary):
	# Does this node have replicated properties?
	const key := REPCO.META_REPLICATE_SCENE
	if root.has_meta(key):
		data[root] = null
	
	# Setup signals on this node.
	if not root.is_node_ready():
		await root.ready
	root.child_entered_tree.connect(_node_child_entered_zone)
	root.tree_exited.connect(_node_exit_zone, CONNECT_ONE_SHOT)
	
	# Continue iteration.
	for child in root.get_children():
		_node_enter_zone(child, data)

func _node_exit_zone(node: Node):
	replication_nodes.erase(node)
	node.child_entered_tree.disconnect(_node_child_entered_zone)

func _node_child_entered_zone(node: Node):
	const key := REPCO.META_REPLICATE_SCENE
	if node.has_meta(key):
		var replication_subnodes := {}
		await _node_enter_zone(node, replication_subnodes)
		replicate_to_interest(replication_subnodes)
		replication_nodes.merge(replication_subnodes)

## Given a set of Nodes, convert it to data for a client to replicate.
func get_replication_rpc_data(for_peer: int, node_set: Dictionary) -> Dictionary:
	"""
	{
		node_path: [
			[-1, property_values, owner]
		],
		parent_path: [
			[index, property_values, owner]
		]
	}
	"""
	var replication_rpc_data := {}
	for node: Node in node_set:
		var property_values := []
		var node_owner := REPCO.get_node_owner(node)
		var data_array := [0, property_values, node_owner]
		var target_node_path := NodePath()
		if node != scene:
			target_node_path = scene.get_path_to(node.get_parent())
			data_array[0] = ReplicationCacheManager.get_index(node.scene_file_path)
		else:
			data_array[0] = -1
		replication_rpc_data.get_or_add(target_node_path, []).append(data_array)
		
		var replication_data: Dictionary = node.get_meta(REPCO.META_SYNC_PROPERTIES, {})
		for property_path: NodePath in replication_data:
			var property_data: Array = replication_data[property_path]
			match property_data[1]:  # match receive filter
				REPCO.PeerFilter.SERVER:
					continue
				REPCO.PeerFilter.OWNER_SERVER:
					if for_peer != node_owner:
						continue
			var node_path := NodePath(property_path.get_concatenated_names())
			var prop_path := NodePath(property_path.get_concatenated_subnames())
			var target_node := node.get_node(node_path) if node_path else node
			var value := target_node.get_indexed(prop_path)
			property_values.append(value)
	return replication_rpc_data

## When called on a client, replicates nodes from a get_replication_rpc_data data structure.
@rpc
func set_replication_rpc_data(replication_rpc_data: Dictionary):
	for node_path: NodePath in replication_rpc_data:
		for node_data: Array in replication_rpc_data[node_path]:
			var node_scene_index: int = node_data[0]
			var node_property_values: Array = node_data[1]
			var node_owner: int = node_data[2]
			
			var target_node: Node = scene.get_node_or_null(node_path) if node_path else scene
			var parent_node: Node
			if not target_node:
				push_warning("Zone.set_replication_rpc_data could not find target node %s" % node_path)
				continue
			if node_scene_index != -1:
				parent_node = target_node
				var scene_path := ReplicationCacheManager.get_scene_file_path(node_scene_index)
				target_node = load(scene_path).instantiate()
			
			var replication_data: Dictionary = target_node.get_meta(REPCO.META_SYNC_PROPERTIES, {})
			var replication_data_keys := replication_data.keys()
			var true_idx := -1
			for idx: int in replication_data_keys.size():
				var property_path: NodePath = replication_data_keys[idx]
				var property_data: Array = replication_data[property_path]
				match property_data[1]:  # match receive filter
					REPCO.PeerFilter.SERVER:
						continue
					REPCO.PeerFilter.OWNER_SERVER:
						if mp.local_peer != node_owner:
							continue
				true_idx += 1
				
				var prop_node_path := NodePath(property_path.get_concatenated_names())
				var prop_path := NodePath(property_path.get_concatenated_subnames())
				
				var prop_node := target_node.get_node(prop_node_path) if prop_node_path else target_node
				var value: Variant = node_property_values[true_idx]
				prop_node.set_indexed(prop_path, value)
			
			if node_owner != 1:
				target_node.set_meta(REPCO.META_OWNER, node_owner)
			
			if node_scene_index != -1:
				parent_node.add_child(target_node)

func replicate_to_interest(node_set: Dictionary):
	for peer in interest:
		var replication_rpc_data := get_replication_rpc_data(peer, node_set)
		set_replication_rpc_data.rpc_id(peer, replication_rpc_data)

#endregion

## Finds the Zone associated with a given Node.
static func fetch(node: Node, mp: MultiplayerRoot = null) -> Zone:
	if not mp:
		mp = MultiplayerRoot.fetch(node)
	if not mp:
		return null
	return mp.get_service(ZoneService).get_node_zone(node)
