@tool
extends VBoxContainer

const ReplicationEditor = preload("res://addons/godaemon_multiplayer/replication/replication_editor.gd")
const ReplicationConfigBase_ = preload("res://addons/godaemon_multiplayer/replication/editor/replication_config_base.gd")

var configs: Array[ReplicationConfigBase_] = []

@onready var editor: ReplicationEditor = owner

var old_script: Script = null

func _set_script(script: Script):
	var args := get_arguments(script)
	var names := args.map(arg_to_name)
	_clear_inherited()
	
	# remove old scripts
	for tscn: ReplicationConfigBase_ in configs.duplicate():
		#print('if %s not in %s:' % [arg_to_name(tscn.argument), names])
		
		if arg_to_name(tscn.argument) not in names or old_script != script:
			remove_child(tscn)
			tscn.queue_free()
			configs.erase(tscn)
			#print('removing %s' % arg_to_name(tscn.argument))
	
	old_script = script
	
	# add new scripts
	for arg in args:
		if not arg:
			continue
		
		var exists := false
		for config in configs:
			# it already exists
			if arg_to_name(config.argument) == arg_to_name(arg):
				exists = true
				break
		
		if not exists:
			var config := get_tscn()
			config.argument = arg
			config._script = ReplicationData.get_script_replication(script)
			config._config = arg_to_config(script, arg)
			add_child(config)
			configs.append(config)
			#print('adding %s' % arg_to_name(arg))
	
	_add_inherited(script, true)

func request_update():
	ReplicationData.validate_script_replication(editor._current_script)
	_set_script(editor._current_script)

var inherited_tscns := []

func _clear_inherited():
	for i in inherited_tscns.duplicate():
		i.queue_free()
		remove_child(i)
	inherited_tscns.clear()

func _add_inherited(script: Script, first := true):
	if not script:
		return
	var new := script.get_base_script()
	if not new or script == new:
		return
	script = new
	
	for arg in get_arguments(script):
		
		var exists := false
		for config in configs:
			# it already exists
			#print('checking %s == %s' % [arg_to_name(config.argument), arg_to_name(arg)])
			if arg_to_name(config.argument) == arg_to_name(arg):
				#print('success')
				exists = true
				break
		if exists:
			continue
		
		var existing_c := arg_to_config(script, arg, false)
		if not existing_c:
			continue
		
		if first:
			var spacer := HSeparator.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.custom_minimum_size = Vector2(0, 16)
			add_child(spacer)
			inherited_tscns.append(spacer)
			first = false
		
		var config := get_tscn()
		config.argument = arg
		config._script = ReplicationData.get_script_replication(script)
		config._config = existing_c
		config.inherited = true
		add_child(config)
		inherited_tscns.append(config)
	
	_add_inherited(script, first)

func get_arguments(s: Script) -> Array:
	return []

func arg_to_config(script: Script, arg: Variant, make := true) -> ReplicationConfigBase:
	return null

func arg_to_name(arg: Variant) -> String:
	return ''

func get_tscn() -> ReplicationConfigBase_:
	return null
