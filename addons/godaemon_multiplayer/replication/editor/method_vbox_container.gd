@tool
extends "res://addons/godaemon_multiplayer/replication/editor/config_vbox_container.gd"

const METHOD_REPLICATION_CONFIG = preload("res://addons/godaemon_multiplayer/replication/editor/method_replication_config.tscn")
const MethodReplicationConfig = preload("res://addons/godaemon_multiplayer/replication/editor/method_replication_config.gd")

func _set_script(script: Script):
	if script:
		# Create method configs to fit our arguments.
		var sr := ReplicationData.get_script_replication(script)
		if sr:
			var args := get_arguments(script)
			var changed := false
			
			for config in sr.method_config.duplicate():
				var found := false
				for a in args:
					if config.name == arg_to_name(a):
						found = true
						break
				if not found:
					# This config is dead.
					sr.method_config.erase(config)
					changed = true
	
			if changed:
				sr.method_config = sr.method_config
	
	super(script)

func get_arguments(s: Script) -> Array:
	if not s:
		return []
	var methods := s.get_script_method_list()
	var rpcs := s.get_rpc_config()
	if not rpcs:
		return []
	var parent := s.get_base_script()
	if parent:
		for key in parent.get_rpc_config():
			rpcs.erase(key)
	return methods.filter(func (x: Dictionary): return x.name in rpcs)

func arg_to_name(arg: Variant) -> String:
	return arg.name

func arg_to_config(script: Script, arg: Variant, make := false) -> ReplicationConfigBase:
	var sr := ReplicationData.get_script_replication(script)
	if not sr:
		return null
	var config_name := arg_to_name(arg)
	var config := sr.get_method_config(config_name)
	if not config and make:
		config = ReplicationMethodConfig.new()
		config.name = config_name
		sr.method_config.append(config)
		sr.method_config = sr.method_config
	return config

func get_tscn() -> MethodReplicationConfig:
	return METHOD_REPLICATION_CONFIG.instantiate()
