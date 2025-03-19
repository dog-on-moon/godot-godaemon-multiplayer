@tool
extends Resource
class_name ReplicationData
## Stores project-wide replication information for scripts.

const SAVE_PATH := "res://addons/godaemon_multiplayer/replication/data/replication_data.tres"

@export var script_replications: Array[ScriptReplication] = []

@export_tool_button("Save", "Save") var __save = func ():
	ReplicationData.save()

@export_tool_button("Reload", "Reload") var __reload = func ():
	ReplicationData._data = null
	ReplicationData._load()

var _script_replication_map: Dictionary[Script, ScriptReplication] = {}

static var _data: ReplicationData

#region Script Replication API

## Returns a script's replication data.
## Returns null if it does not exist.
## Note that parent classes may have replication, though -- check get_replication_parent_depth()
static func get_script_replication(script: Script, parent_depth := 0) -> ScriptReplication:
	_load()
	if not script:
		return null
	for i in parent_depth:
		script = script.get_base_script()
		if not script:
			return null
	var sr: ScriptReplication = _data._script_replication_map.get(script, null)
	if sr:
		sr.setup_cache()
	return sr

static func get_base_script_replication(script: Script) -> ScriptReplication:
	var d := get_replication_parent_depth(script)
	if d == -1:
		return null
	return get_script_replication(script, d)

static func has_script_replication(script: Script) -> bool:
	return get_replication_parent_depth(script) != -1

static var _parent_depth_cache: Dictionary[Script, int] = {}

## Returns the initial replication parent depth for a script's replication.
## If -1, the script in question certainly has no script replication whatsoever.
static func get_replication_parent_depth(base_script: Script) -> int:
	if not base_script:
		return -1
	if base_script in _parent_depth_cache:
		return _parent_depth_cache[base_script]
	var parent_depth := -1
	var script := base_script
	while true:
		parent_depth += 1
		if get_script_replication(script):
			_parent_depth_cache[base_script] = parent_depth
			return parent_depth
		script = script.get_base_script()
		if not script:
			break
	_parent_depth_cache[base_script] = -1
	return -1

## Returns all script replications for a given script.
static func get_all_script_replications(script: Script) -> Array[ScriptReplication]:
	var srs: Array[ScriptReplication] = []
	if not script:
		return srs
	while true:
		var sr := get_script_replication(script)
		if sr:
			srs.append(sr)
		script = script.get_base_script()
		if not script:
			break
	return srs

## Toggles a script's replication.
static func toggle_script_replication(script: Script, mode: bool) -> ScriptReplication:
	_load()
	if not script:
		return null
	if not mode:
		if script in _data._script_replication_map:
			_data.script_replications.erase(_data._script_replication_map[script])
			_data._script_replication_map.erase(script)
			save()
		return null
	elif not get_script_replication(script):
		var rep := ScriptReplication.new()
		rep._script = script
		_data.script_replications.append(rep)
		_data._script_replication_map[script] = rep
		if not rep.changed.is_connected(save):
			rep.changed.connect(save)
		save()
		return rep
	return get_script_replication(script)

## Validates a script's replication state.
static func validate_script_replication(script: Script, make_exist := false):
	var replication := get_script_replication(script)
	if replication:
		# Kill replication data if the script has Nothingdog.
		if (
			not replication.method_config
			and not replication.property_config
			and not replication.signal_config
			and not script.get_rpc_config()
				):
			toggle_script_replication(script, false)
	else:
		# Setup replication data if the script has RPC stuff.
		if script.get_rpc_config() or make_exist:
			toggle_script_replication(script, true)

#endregion

#region Property Harvest API

## Harvests a object's property values for a target peer.
static func get_object_property_values(object: Node, peer := 0) -> Array:
	# Calculate the property values for this script.
	var object_property_values := []
	for sr in get_all_script_replications(object.get_script()):
		for config in sr.property_config:
			# We replicate all listed properties to the client initially.
			# Though, only be sure to replicate those that they care about.
			if not config.can_they_recv(object, peer) and peer != 0:
				continue
			# Get the property value for this object.
			object_property_values.append(object.get(config.name))
	return object_property_values

## Applies a object's property values for the local peer.
static func apply_object_property_values(mp: MultiplayerRoot, object: Node, object_property_values: Array, peer := -1):
	var true_idx := -1
	if peer == -1:
		peer = mp.local_peer
	for sr in get_all_script_replications(object.get_script()):
		for config in sr.property_config:
			if not config.can_they_recv(object, peer) and peer != 0:
				continue
			true_idx += 1
			object.set(config.name, object_property_values[true_idx])

#endregion

#region Method Cache API

## Gets a object's method name to its config.
static func object_method_to_config(object: Node, n: String) -> ReplicationMethodConfig:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_method_to_config(script, n)
	if cache:
		return cache
	
	# Begin looping.
	for sr in get_all_script_replications(script):
		# Look for the config.
		var c := sr.get_method_config(n)
		if c:
			_put_object_method_to_config(script, n, c)
			return c
	
	# Could not find.
	return null

## Converts a object's method name to an index.
static func object_method_to_idx(object: Node, c: ReplicationMethodConfig) -> int:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_method_to_idx(script, c)
	if cache != -1:
		return cache
	
	# Begin looping.
	var current_idx := 0
	for sr in get_all_script_replications(script):
		# Look for the config in this SR.
		if sr.has_method_config(c):
			var result_idx := current_idx + sr.get_idx_from_method_config(c)
			_put_object_method_to_idx(script, c, result_idx)
			return result_idx
		else:
			current_idx += sr.method_config.size()
	
	# Name was not found/defined.
	return -1

## Converts a object's method index back into its config.
static func object_idx_to_method(object: Node, idx: int) -> ReplicationMethodConfig:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_idx_to_method(script, idx)
	if cache:
		return cache
	var base_sr := get_base_script_replication(script)
	if not base_sr:
		return null
	
	# Begin looping.
	var start_idx := idx
	for sr in get_all_script_replications(script):
		# Look for the config in this SR.
		var config_count := sr.method_config.size()
		if idx < config_count:
			var config := sr.get_method_config_from_idx(idx)
			_put_object_idx_to_method(script, start_idx, config)
			return config
		else:
			idx -= config_count
			if idx < 0:
				break
	
	# Name was not found/defined.
	return null

static var _object_method_to_config_cache := {}

static func _put_object_method_to_config(sr: Script, n: String, c: ReplicationMethodConfig):
	if sr not in _object_method_to_config_cache:
		_object_method_to_config_cache[sr] = {}
	_object_method_to_config_cache[sr][n] = c

static func _get_object_method_to_config(sr: Script, n: String) -> ReplicationMethodConfig:
	if sr not in _object_method_to_config_cache:
		return null
	return _object_method_to_config_cache[sr].get(n, null)

static var _object_method_to_idx_cache := {}

static func _put_object_method_to_idx(sr: Script, c: ReplicationMethodConfig, idx: int):
	if sr not in _object_method_to_idx_cache:
		_object_method_to_idx_cache[sr] = {}
	_object_method_to_idx_cache[sr][c] = idx

static func _get_object_method_to_idx(sr: Script, c: ReplicationMethodConfig) -> int:
	if sr not in _object_method_to_idx_cache:
		return -1
	return _object_method_to_idx_cache[sr].get(c, -1)

static var _object_idx_to_method_cache := {}

static func _put_object_idx_to_method(sr: Script, idx: int, c: ReplicationMethodConfig):
	if sr not in _object_idx_to_method_cache:
		_object_idx_to_method_cache[sr] = {}
	_object_idx_to_method_cache[sr][idx] = c

static func _get_object_idx_to_method(sr: Script, idx: int) -> ReplicationMethodConfig:
	if sr not in _object_idx_to_method_cache:
		return null
	return _object_idx_to_method_cache[sr].get(idx, null)

#endregion

#region Property Cache API

## Gets a object's property name to its config.
static func object_property_to_config(object: Node, n: String) -> ReplicationPropertyConfig:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_property_to_config(script, n)
	if cache:
		return cache
	var base_sr := get_base_script_replication(script)
	if not base_sr:
		return null
	
	# Begin looping.
	for sr in get_all_script_replications(script):
		# Look for the config.
		var c := sr.get_property_config(n)
		if c:
			_put_object_property_to_config(script, n, c)
			return c
	
	# Could not find.
	return null

## Converts a object's property name to an index.
static func object_property_to_idx(object: Node, c: ReplicationPropertyConfig) -> int:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_property_to_idx(script, c)
	if cache != -1:
		return cache
	var base_sr := get_base_script_replication(script)
	if not base_sr:
		return -1
	
	# Begin looping.
	var current_idx := 0
	for sr in get_all_script_replications(script):
		# Look for the config in this SR.
		if sr.has_property_config(c):
			var result_idx := current_idx + sr.get_idx_from_property_config(c)
			_put_object_property_to_idx(script, c, result_idx)
			return result_idx
		else:
			current_idx += sr.property_config.size()
	
	# Name was not found/defined.
	return -1

## Converts a object's property index back into its config.
static func object_idx_to_property(object: Node, idx: int) -> ReplicationPropertyConfig:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_idx_to_property(script, idx)
	if cache:
		return cache
	
	# Begin looping.
	var start_idx := idx
	for sr in get_all_script_replications(script):
		# Look for the config in this SR.
		var config_count := sr.property_config.size()
		if idx < config_count:
			var config := sr.get_property_config_from_idx(idx)
			_put_object_idx_to_property(script, start_idx, config)
			return config
		else:
			idx -= config_count
			if idx < 0:
				break
	
	# Name was not found/defined.
	return null

static var _object_property_to_config_cache := {}

static func _put_object_property_to_config(sr: Script, n: String, c: ReplicationPropertyConfig):
	if sr not in _object_property_to_config_cache:
		_object_property_to_config_cache[sr] = {}
	_object_property_to_config_cache[sr][n] = c

static func _get_object_property_to_config(sr: Script, n: String) -> ReplicationPropertyConfig:
	if sr not in _object_property_to_config_cache:
		return null
	return _object_property_to_config_cache[sr].get(n, null)

static var _object_property_to_idx_cache := {}

static func _put_object_property_to_idx(sr: Script, c: ReplicationPropertyConfig, idx: int):
	if sr not in _object_property_to_idx_cache:
		_object_property_to_idx_cache[sr] = {}
	_object_property_to_idx_cache[sr][c] = idx

static func _get_object_property_to_idx(sr: Script, c: ReplicationPropertyConfig) -> int:
	if sr not in _object_property_to_idx_cache:
		return -1
	return _object_property_to_idx_cache[sr].get(c, -1)

static var _object_idx_to_property_cache := {}

static func _put_object_idx_to_property(sr: Script, idx: int, c: ReplicationPropertyConfig):
	if sr not in _object_idx_to_property_cache:
		_object_idx_to_property_cache[sr] = {}
	_object_idx_to_property_cache[sr][idx] = c

static func _get_object_idx_to_property(sr: Script, idx: int) -> ReplicationPropertyConfig:
	if sr not in _object_idx_to_property_cache:
		return null
	return _object_idx_to_property_cache[sr].get(idx, null)

#endregion

#region Signal Cache API

## Gets a object's signal name to its config.
static func object_signal_to_config(object: Node, n: String) -> ReplicationSignalConfig:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_signal_to_config(script, n)
	if cache:
		return cache
	
	# Begin looping.
	for sr in get_all_script_replications(script):
		# Look for the config.
		var c := sr.get_signal_config(n)
		if c:
			_put_object_signal_to_config(script, n, c)
			return c
	
	# Could not find.
	return null

## Converts a object's signal name to an index.
static func object_signal_to_idx(object: Node, c: ReplicationSignalConfig) -> int:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_signal_to_idx(script, c)
	if cache != -1:
		return cache
	
	# Begin looping.
	var current_idx := 0
	for sr in get_all_script_replications(script):
		# Look for the config in this SR.
		if sr.has_signal_config(c):
			var result_idx := current_idx + sr.get_idx_from_signal_config(c)
			_put_object_signal_to_idx(script, c, result_idx)
			return result_idx
		else:
			current_idx += sr.signal_config.size()
	
	# Name was not found/defined.
	return -1

## Converts a object's signal index back into its config.
static func object_idx_to_signal(object: Node, idx: int) -> ReplicationSignalConfig:
	# Check cache.
	var script: Script = object.get_script()
	var cache := _get_object_idx_to_signal(script, idx)
	if cache:
		return cache
	
	# Begin looping.
	var start_idx := idx
	for sr in get_all_script_replications(script):
		# Look for the config in this SR.
		var config_count := sr.signal_config.size()
		if idx < config_count:
			var config := sr.get_signal_config_from_idx(idx)
			_put_object_idx_to_signal(script, start_idx, config)
			return config
		else:
			idx -= config_count
			if idx < 0:
				break
	
	# Name was not found/defined.
	return null

static var _object_signal_to_config_cache := {}

static func _put_object_signal_to_config(sr: Script, n: String, c: ReplicationSignalConfig):
	if sr not in _object_signal_to_config_cache:
		_object_signal_to_config_cache[sr] = {}
	_object_signal_to_config_cache[sr][n] = c

static func _get_object_signal_to_config(sr: Script, n: String) -> ReplicationSignalConfig:
	if sr not in _object_signal_to_config_cache:
		return null
	return _object_signal_to_config_cache[sr].get(n, null)

static var _object_signal_to_idx_cache := {}

static func _put_object_signal_to_idx(sr: Script, c: ReplicationSignalConfig, idx: int):
	if sr not in _object_signal_to_idx_cache:
		_object_signal_to_idx_cache[sr] = {}
	_object_signal_to_idx_cache[sr][c] = idx

static func _get_object_signal_to_idx(sr: Script, c: ReplicationSignalConfig) -> int:
	if sr not in _object_signal_to_idx_cache:
		return -1
	return _object_signal_to_idx_cache[sr].get(c, -1)

static var _object_idx_to_signal_cache := {}

static func _put_object_idx_to_signal(sr: Script, idx: int, c: ReplicationSignalConfig):
	if sr not in _object_idx_to_signal_cache:
		_object_idx_to_signal_cache[sr] = {}
	_object_idx_to_signal_cache[sr][idx] = c

static func _get_object_idx_to_signal(sr: Script, idx: int) -> ReplicationSignalConfig:
	if sr not in _object_idx_to_signal_cache:
		return null
	return _object_idx_to_signal_cache[sr].get(idx, null)

#endregion

#endregion

#region Read/Write

## Saves storage to disk.
static func save() -> void:
	if not Engine.is_editor_hint():
		return
	
	_data.take_over_path(SAVE_PATH)
	ResourceSaver.save(_data, SAVE_PATH)

static func _load():
	if _data: return
	if not FileAccess.file_exists(SAVE_PATH):
		_data = ReplicationData.new()
	else:
		_data = load(SAVE_PATH)
		
		for rep: ScriptReplication in _data.script_replications:
			_data._script_replication_map[rep._script] = rep
			if Engine.is_editor_hint() and not rep.changed.is_connected(save):
				rep.changed.connect(save)

#endregion
