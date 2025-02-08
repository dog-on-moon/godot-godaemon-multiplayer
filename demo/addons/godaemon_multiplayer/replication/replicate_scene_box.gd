@tool
extends CheckBox

var current_scene_root: Node = null:
	set(x):
		if current_scene_root != x:
			current_scene_root = x
			_update()

func _ready() -> void:
	current_scene_root = get_tree().edited_scene_root
	toggled.connect(_toggle)

func _process(delta: float) -> void:
	current_scene_root = get_tree().edited_scene_root

func _update():
	set_pressed_no_signal(current_scene_root.has_meta(ReplicationService.KEY_REPLICATE_CURRENT_SCENE))

func _toggle(m: bool):
	if m:
		current_scene_root.set_meta(ReplicationService.KEY_REPLICATE_CURRENT_SCENE, 0)
	else:
		current_scene_root.set_meta(ReplicationService.KEY_REPLICATE_CURRENT_SCENE, null)
