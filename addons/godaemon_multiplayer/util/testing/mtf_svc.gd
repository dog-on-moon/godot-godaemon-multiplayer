extends SubViewportContainer
# SubViewportContainer for use in the MTF (multiplayer test frame)
# (and we're so proud of her)

## Determines if input events are active for this SubViewportContainer.
@export var active := false:
	set(x):
		active = x
		for b in border:
			b.visible = x

## Creates a client node or server node in ready.
@export var client := true

var sub_viewport: SubViewport
var mp: MultiplayerRoot
var border: Array[Control] = []

var config: MultiplayerConfig:
	set(x):
		config = x
		if mp:
			mp.configuration = config

func _ready() -> void:
	const COLOR := Color(1, 1, 1, 1)
	const PADDING := 1
	const BORDER_PARAMS := {
		Control.PRESET_TOP_WIDE: [Vector2(0, PADDING), Vector2.ZERO],
		Control.PRESET_LEFT_WIDE: [Vector2(PADDING, 0), Vector2.ZERO],
		Control.PRESET_BOTTOM_WIDE: [Vector2(0, PADDING), Vector2(0, -PADDING)],
		Control.PRESET_RIGHT_WIDE: [Vector2(PADDING, 0), Vector2(-PADDING, 0)],
	}
	for preset in BORDER_PARAMS:
		var b := ColorRect.new()
		b.visible = false
		b.color = COLOR
		b.custom_minimum_size = BORDER_PARAMS[preset][0]
		b.set_anchors_and_offsets_preset(preset)
		border.append(b)
		add_child(b)
		b.position += BORDER_PARAMS[preset][1]
	
	stretch = true
	sub_viewport = SubViewport.new()
	sub_viewport.name = "SubViewport"
	sub_viewport.size_2d_override = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	sub_viewport.size_2d_override_stretch = true
	mp = ClientRoot.new() if client else ServerRoot.new()
	mp.name = "ClientRoot" if client else "ServerRoot"
	mp.multiconnect_on_ready = false
	mp.configuration = config
	sub_viewport.add_child(mp)
	update_render_properties(get_viewport(), sub_viewport)
	add_child(sub_viewport)

func _propagate_input_event(event: InputEvent):
	return active

func update_render_properties(from_viewport: Viewport, to_viewport: Viewport):
	to_viewport.snap_2d_transforms_to_pixel = from_viewport.snap_2d_transforms_to_pixel
	to_viewport.snap_2d_vertices_to_pixel = from_viewport.snap_2d_vertices_to_pixel
	to_viewport.msaa_2d = from_viewport.msaa_2d
	to_viewport.msaa_3d = from_viewport.msaa_3d
	to_viewport.screen_space_aa = from_viewport.screen_space_aa
	to_viewport.use_taa = from_viewport.use_taa
	to_viewport.use_debanding = from_viewport.use_debanding
	to_viewport.use_occlusion_culling = from_viewport.use_occlusion_culling
	to_viewport.mesh_lod_threshold = from_viewport.mesh_lod_threshold
	to_viewport.debug_draw = from_viewport.debug_draw
	to_viewport.use_hdr_2d = from_viewport.use_hdr_2d
	to_viewport.scaling_3d_mode = from_viewport.scaling_3d_mode
	to_viewport.scaling_3d_scale = from_viewport.scaling_3d_scale
	to_viewport.texture_mipmap_bias = from_viewport.texture_mipmap_bias
	to_viewport.fsr_sharpness = from_viewport.fsr_sharpness
	to_viewport.vrs_mode = from_viewport.vrs_mode
	to_viewport.vrs_update_mode = from_viewport.vrs_update_mode
	to_viewport.vrs_texture = from_viewport.vrs_texture
	to_viewport.canvas_item_default_texture_filter = from_viewport.canvas_item_default_texture_filter
	to_viewport.canvas_item_default_texture_repeat = from_viewport.canvas_item_default_texture_repeat
	to_viewport.audio_listener_enable_2d = from_viewport.audio_listener_enable_2d
	to_viewport.audio_listener_enable_3d = from_viewport.audio_listener_enable_3d
	to_viewport.physics_object_picking = from_viewport.physics_object_picking
	to_viewport.physics_object_picking_sort = from_viewport.physics_object_picking_sort
	to_viewport.physics_object_picking_first_only = from_viewport.physics_object_picking_first_only
	to_viewport.gui_disable_input = from_viewport.gui_disable_input
	to_viewport.gui_snap_controls_to_pixels = from_viewport.gui_snap_controls_to_pixels
	to_viewport.gui_embed_subwindows = from_viewport.gui_embed_subwindows
	to_viewport.sdf_oversize = from_viewport.sdf_oversize
	to_viewport.sdf_scale = from_viewport.sdf_scale
	to_viewport.positional_shadow_atlas_size = from_viewport.positional_shadow_atlas_size
	to_viewport.positional_shadow_atlas_16_bits = from_viewport.positional_shadow_atlas_16_bits
	to_viewport.positional_shadow_atlas_quad_0 = from_viewport.positional_shadow_atlas_quad_0
	to_viewport.positional_shadow_atlas_quad_1 = from_viewport.positional_shadow_atlas_quad_1
	to_viewport.positional_shadow_atlas_quad_2 = from_viewport.positional_shadow_atlas_quad_2
	to_viewport.positional_shadow_atlas_quad_3 = from_viewport.positional_shadow_atlas_quad_3
