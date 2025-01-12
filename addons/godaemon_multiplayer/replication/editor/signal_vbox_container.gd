@tool
extends "res://addons/godaemon_multiplayer/replication/editor/config_vbox_container.gd"

var PROPERTY_TYPE_FILTER := PackedInt32Array([TYPE_SIGNAL])

const SIGNAL_REPLICATION_CONFIG = preload("res://addons/godaemon_multiplayer/replication/editor/signal_replication_config.tscn")
const SignalReplicationConfig = preload("res://addons/godaemon_multiplayer/replication/editor/signal_replication_config.gd")

@onready var new_property: Button = %NewSignal

@onready var signal_icon := EditorInterface.get_editor_theme().get_icon(&"Signal", &"EditorIcons")

func _ready() -> void:
	new_property.pressed.connect(
		func ():
			var script := editor._current_script
			if not script:
				return
			var obj: Object = script.new()
			var signals := obj.get_signal_list()
			obj.free()
			
			var w := AcceptDialog.new()
			w.title = "Select Signal"
			w.get_ok_button().queue_free()
			
			var tree := Tree.new()
			tree.create_item()
			tree.hide_root = true
			tree.columns = 1
			tree.custom_minimum_size = Vector2(128, 256)
			
			for s in signals:
				var item := tree.create_item()
				item.set_text(0, s.name)
				item.set_icon(0, signal_icon)
			
			tree.item_activated.connect(
				func ():
					var idx := tree.get_selected().get_index()
					w.queue_free()
					var s := signals[idx]
					
					var sr := ReplicationData.get_script_replication(script)
					if not sr:
						sr = ReplicationData.toggle_script_replication(script, true)
					if sr:
						if not sr.get_signal_config(s.name):
							var config := ReplicationSignalConfig.new()
							config.name = s.name
							update_config_arg_count(script, config)
							sr.signal_config.append(config)
							sr.signal_config = sr.signal_config
							_set_script(script)
			)
			
			w.add_child(tree)
			
			EditorInterface.popup_dialog_centered(w, Vector2i(32, 32))
	)

func _set_script(script: Script):
	if script:
		# Remove dead definitions.
		var sr := ReplicationData.get_script_replication(script)
		if sr:
			var args := get_arguments(script)
			var changed := false
			
			for config in sr.signal_config.duplicate():
				var found := false
				for a in args:
					if config.name == arg_to_name(a):
						found = true
						update_config_arg_count(script, config)
						break
				if not found:
					# This config is dead.
					sr.signal_config.erase(config)
					changed = true
	
			if changed:
				sr.signal_config = sr.signal_config
	super(script)

func get_arguments(s: Script) -> Array:
	if not s:
		return []
	var sr := ReplicationData.get_script_replication(s)
	if not sr:
		return []
	var obj: Object = s.new()
	var args := obj.get_signal_list()
	obj.free()
	
	return args.filter(func (x): return arg_to_config(s, x, false) != null)

func arg_to_name(arg: Variant) -> String:
	return arg.name

func arg_to_config(script: Script, arg: Variant, make := true) -> ReplicationSignalConfig:
	var sr := ReplicationData.get_script_replication(script)
	if not sr:
		return null
	var config_name := arg_to_name(arg)
	var config := sr.get_signal_config(config_name)
	if not config and make:
		config = ReplicationSignalConfig.new()
		config.name = config_name
		sr.signal_config.append(config)
		sr.signal_config = sr.signal_config
	return config

func get_tscn() -> SignalReplicationConfig:
	var c := SIGNAL_REPLICATION_CONFIG.instantiate()
	c.request_update.connect(request_update)
	return c

static func update_config_arg_count(s: Script, c: ReplicationSignalConfig):
	var d := signal_name_to_dict(s, c.name)
	if d:
		c.arg_count = d.args.size()
	else:
		print('Could not update signal arg count')

static func signal_name_to_dict(s: Script, n: String) -> Dictionary:
	for asdf in s.get_script_signal_list():
		if asdf.name == n:
			return asdf
	return {}
