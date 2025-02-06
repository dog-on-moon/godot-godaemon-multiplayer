@tool
extends "res://addons/godaemon_multiplayer/replication/editor/replication_config_base.gd"

var config: ReplicationSignalConfig:
	get: return _config

func _ready() -> void:
	super()
	if not argument or not config:
		return
	
	delete_button.pressed.connect(
		func ():
			_script.signal_config.erase(config)
			_script.signal_config = _script.signal_config
			request_update.emit()
	)
	
	config_name.text = argument.name
	config_name.icon = editor_theme.get_icon(&"Signal", &"EditorIcons")
	
	debug_print.set_pressed_no_signal(config.get_debug_print())
	debug_print.toggled.connect(config.set_debug_print)
