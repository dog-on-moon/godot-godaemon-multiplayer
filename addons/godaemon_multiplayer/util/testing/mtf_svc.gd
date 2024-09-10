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
	const BORDER_PARAMS: Dictionary[Control.LayoutPreset, Array] = {
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
	add_child(sub_viewport)

func _propagate_input_event(event: InputEvent):
	return active
