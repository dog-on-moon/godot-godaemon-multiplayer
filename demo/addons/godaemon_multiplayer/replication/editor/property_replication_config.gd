@tool
extends "res://addons/godaemon_multiplayer/replication/editor/replication_config_base.gd"

@onready var angular_lerp: CheckBox = %AngularLerp

var config: ReplicationPropertyConfig:
	get: return _config

func _ready() -> void:
	super()
	if not argument or not config:
		return
	
	delete_button.pressed.connect(
		func ():
			_script.property_config.erase(config)
			_script.property_config = _script.property_config
			request_update.emit()
	)
	
	config_name.text = argument.name
	config_name.icon = editor_theme.get_icon(type_string(argument.type), &"EditorIcons")
	
	sync_mode.selected = int(config.sync)
	sync_mode.item_selected.connect(func (x): config.sync = x)
	
	dont_sync_to_owner.set_pressed_no_signal(config.get_robns())
	dont_sync_to_owner.toggled.connect(config.set_robns)
	
	debug_print.set_pressed_no_signal(config.get_debug_print())
	debug_print.toggled.connect(config.set_debug_print)
	
	angular_lerp.set_pressed_no_signal(config.get_angular_lerp())
	angular_lerp.toggled.connect(config.set_angular_lerp)

func _update():
	super()
	subtitle.text = ("[b]%s[/b]  " % config.get_sync_text()) + subtitle.text
