@tool
extends "res://addons/godaemon_multiplayer/replication/editor/replication_config_base.gd"

var config: ReplicationMethodConfig:
	get: return _config

func _ready() -> void:
	super()
	if not argument:
		return
	
	config_name.text = create_method_signature(argument)
	config_name.icon = editor_theme.get_icon(&"Callable", &"EditorIcons")
	
	ratelimit_spinbox.value = config.ratelimit
	ratelimit_spinbox.value_changed.connect(func (x): config.ratelimit = x)
	
	call_local.set_pressed_no_signal(config.get_call_local())
	call_local.toggled.connect(config.set_call_local)
	
	debug_print.set_pressed_no_signal(config.get_debug_print())
	debug_print.toggled.connect(config.set_debug_print)

static func create_method_signature(method_data: Dictionary) -> String:
	var signature: String = method_data.name + "("
	var arg_count := 0
	var default_start_idx: int = method_data.args.size() - method_data.default_args.size()
	for arg: Dictionary in method_data.args:
		if arg_count != 0:
			signature += ", "
		signature += "%s: %s" % [arg.name, type_string(arg.type) if not arg.class_name else arg.class_name]
		if arg_count >= default_start_idx:
			var default_arg: Variant = method_data.default_args[arg_count - default_start_idx]
			signature += " = %s" % default_arg
		arg_count += 1
	signature += ")"
	return signature
