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
@onready var mp: MultiplayerRoot = MultiplayerRoot.fetch(self)
@onready var zone_service: ZoneService = mp.get_service(ZoneService)

var old_interest := {}

## A dictionary mapping peers to null.
@export var interest := {}:
	set(x):
		interest = x
		if mp:
			for peer in interest:
				if peer not in old_interest:
					interest_added.emit(peer)
			for peer in old_interest:
				if peer not in interest:
					interest_removed.emit(peer)
			old_interest = x

@export var zone_index := 0

## The scene we're in charge of.
var scene: Node

#endregion

#region Rendering

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

func _ready() -> void:
	_setup_rendering()
	if mp.is_client():
		child_entered_tree.connect(
			func (s: Node):
				scene = s
				zone_service.local_client_add_interest(self)
		, CONNECT_ONE_SHOT
		)

func _exit_tree() -> void:
	if mp.is_client():
		zone_service.local_client_remove_interest(self)

## Finds the Zone associated with a given Node.
static func fetch(node: Node, mp: MultiplayerRoot = null) -> Zone:
	if not mp:
		mp = MultiplayerRoot.fetch(node)
	if not mp:
		return null
	return mp.get_service(ZoneService).get_node_zone(node)