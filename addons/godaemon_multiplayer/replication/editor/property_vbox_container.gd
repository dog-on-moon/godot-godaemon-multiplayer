@tool
extends "res://addons/godaemon_multiplayer/replication/editor/config_vbox_container.gd"

var PROPERTY_TYPE_FILTER := PackedInt32Array([
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR2I,
	TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_TRANSFORM2D,
	TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB,
	TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR, TYPE_STRING_NAME,
	TYPE_NODE_PATH, TYPE_DICTIONARY, TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY,
	TYPE_OBJECT,
])

const PROPERTY_REPLICATION_CONFIG = preload("res://addons/godaemon_multiplayer/replication/editor/property_replication_config.tscn")
const PropertyReplicationConfig = preload("res://addons/godaemon_multiplayer/replication/editor/property_replication_config.gd")

@onready var new_property: Button = %NewProperty

func _ready() -> void:
	new_property.pressed.connect(
		func ():
			var script := editor._current_script
			if not script:
				return
			var obj: Object = script.new()
			EditorInterface.popup_property_selector(obj, func (path: NodePath):
				if not path.is_empty():
					var sr := ReplicationData.get_script_replication(script)
					if not sr:
						sr = ReplicationData.toggle_script_replication(script, true)
					if sr:
						if not sr.get_property_config(path.get_subname(0)):
							var config := ReplicationPropertyConfig.new()
							config.name = path.get_subname(0)
							sr.property_config.append(config)
							sr.property_config = sr.property_config
							_set_script(script)
				obj.free()
			, PROPERTY_TYPE_FILTER)
	)


func _set_script(script: Script):
	if script:
		# Remove dead definitions.
		var sr := ReplicationData.get_script_replication(script)
		if sr:
			var args := get_arguments(script)
			var changed := false
			
			for config in sr.property_config.duplicate():
				var found := false
				for a in args:
					if config.name == arg_to_name(a):
						found = true
						break
				if not found:
					# This config is dead.
					sr.property_config.erase(config)
					changed = true
	
			if changed:
				sr.property_config = sr.property_config
	super(script)

func get_arguments(s: Script) -> Array:
	if not s:
		return []
	var sr := ReplicationData.get_script_replication(s)
	if not sr:
		return []
	var obj: Object = s.new()
	var args := obj.get_property_list()
	obj.free()
	
	return args.filter(func (x): return arg_to_config(s, x, false) != null)

func arg_to_name(arg: Variant) -> String:
	return arg.name

func arg_to_config(script: Script, arg: Variant, make := true) -> ReplicationPropertyConfig:
	var sr := ReplicationData.get_script_replication(script)
	if not sr:
		return null
	var config_name := arg_to_name(arg)
	var config := sr.get_property_config(config_name)
	if not config and make:
		config = ReplicationPropertyConfig.new()
		config.name = config_name
		sr.property_config.append(config)
		sr.property_config = sr.property_config
	return config

func get_tscn() -> PropertyReplicationConfig:
	var c := PROPERTY_REPLICATION_CONFIG.instantiate()
	c.request_update.connect(request_update)
	return c
