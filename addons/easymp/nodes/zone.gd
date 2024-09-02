@tool
extends SubViewport
class_name Zone
## A Zone is the root node of all distributed scenes in the EasyMP API.
## After a ServerNode adds a scene, it lives within a Zone.
## The contents can then be automatically replicated to clients
## by assigning peer visibility.

#region Signals

const StaticSignal = preload("res://addons/easymp/util/static_signal.gd")

## Emit this signal from anywhere to update the Zone's rendering options
## to match the game window.
static var update_rendering_mode := StaticSignal.make()

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
## Please call `Zone.update_rendering_mode.emit()` whenever you update the game
## window's rendering settings, so that the Zones will update as well.
var use_window_render_settings := true

#endregion

#region Properties

@onready var zone_root: ZoneRoot = get_parent()

#endregion

#region Getters

## Returns true if the Zone is being ran on the client.
func is_client() -> bool:
	return zone_root.client_node != null or is_local_dev()

## Returns true if the Zone is being ran on the server.
func is_server() -> bool:
	return zone_root.server_node != null

## Returns true if the Zone is being ran as a local scene.
## This is useful for testing and developing areas.
func is_local_dev() -> bool:
	return self == get_tree().current_scene

#endregion

#region Rendering

func _setup_rendering():
	# Set default rendering parameters of the Viewport.
	render_target_clear_mode = CLEAR_MODE_ALWAYS
	render_target_update_mode = UPDATE_WHEN_VISIBLE
	transparent_bg = true
	handle_input_locally = false
	
	if not Engine.is_editor_hint():
		# Copy properties from the window viewport.
		var _window: Window = get_window()
		copy_window_rendering_mode(_window)
		update_rendering_mode.connect(copy_window_rendering_mode.bind(_window))

## Copies the viewport rendering mode from a window.
## If 'use_window_render_settings' is set, this will automatically
## capture parameters from the game window.
func copy_window_rendering_mode(w: Window):
	if not use_window_render_settings:
		return
	snap_2d_transforms_to_pixel = w.snap_2d_transforms_to_pixel
	snap_2d_vertices_to_pixel = w.snap_2d_vertices_to_pixel
	msaa_2d = w.msaa_2d
	msaa_3d = w.msaa_3d
	screen_space_aa = w.screen_space_aa
	use_taa = w.use_taa
	use_debanding = w.use_debanding
	use_occlusion_culling = w.use_occlusion_culling
	mesh_lod_threshold = w.mesh_lod_threshold
	debug_draw = w.debug_draw
	use_hdr_2d = w.use_hdr_2d
	scaling_3d_mode = w.scaling_3d_mode
	scaling_3d_scale = w.scaling_3d_scale
	texture_mipmap_bias = w.texture_mipmap_bias
	fsr_sharpness = w.fsr_sharpness
	vrs_mode = w.vrs_mode
	vrs_update_mode = w.vrs_update_mode
	vrs_texture = w.vrs_texture
	canvas_item_default_texture_filter = w.canvas_item_default_texture_filter
	canvas_item_default_texture_repeat = w.canvas_item_default_texture_repeat
	audio_listener_enable_2d = w.audio_listener_enable_2d
	audio_listener_enable_3d = w.audio_listener_enable_3d
	physics_object_picking = w.physics_object_picking
	physics_object_picking_sort = w.physics_object_picking_sort
	physics_object_picking_first_only = w.physics_object_picking_first_only
	gui_disable_input = w.gui_disable_input
	gui_snap_controls_to_pixels = w.gui_snap_controls_to_pixels
	gui_embed_subwindows = w.gui_embed_subwindows
	sdf_oversize = w.sdf_oversize
	sdf_scale = w.sdf_scale
	positional_shadow_atlas_size = w.positional_shadow_atlas_size
	positional_shadow_atlas_16_bits = w.positional_shadow_atlas_16_bits
	positional_shadow_atlas_quad_0 = w.positional_shadow_atlas_quad_0
	positional_shadow_atlas_quad_1 = w.positional_shadow_atlas_quad_1
	positional_shadow_atlas_quad_2 = w.positional_shadow_atlas_quad_2
	positional_shadow_atlas_quad_3 = w.positional_shadow_atlas_quad_3

#endregion

func _ready() -> void:
	_setup_rendering()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	warnings.append("The Zone class is not meant to be instantiated. It is an internal class use to hold scenes within a ServerNode.")
	return warnings
