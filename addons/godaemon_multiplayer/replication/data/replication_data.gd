@tool
extends Resource
class_name ReplicationData
## Stores project-wide replication information for scripts.

const SAVE_PATH := "res://addons/godaemon_multiplayer/replication/data/replication_data.json"

## Stores script replication for script UIDs.
@export var script_replication_map: Dictionary[int, ScriptReplication] = {}

static var _data: ReplicationData

static func _static_init() -> void:
	_data = _load()
	
	if Engine.is_editor_hint():
		var changed := false
		for uid in _data.script_replication_map.keys():
			# Check if the script still exists.
			var path := uid_to_path(uid)
			if not (path and FileAccess.file_exists(path)):
				_data.script_replication_map.erase(uid)
				changed = true
				continue
			
			# Setup script autosave.
			var rep: ScriptReplication = _data.script_replication_map[uid]
			if not rep.updated.is_connected(save):
				rep.updated.connect(save)
		if changed:
			_data.save.call_deferred()

#region Script Replication API

## Returns a script's replication data.
## Returns null if it does not exist.
static func get_script_replication(script: Script, parent_depth := 0) -> ScriptReplication:
	if not script:
		return null
	for i in parent_depth:
		script = script.get_base_script()
		if not script:
			return null
	var uid := path_to_uid(script.resource_path)
	if uid == -1:
		print('script %s has no uid?' % script.resource_path)
		return null
	return _data.script_replication_map.get(uid, null)

## Toggles a script's replication.
static func toggle_script_replication(script: Script, mode: bool) -> ScriptReplication:
	if not script:
		return null
	var uid := path_to_uid(script.resource_path)
	if not mode:
		_data.script_replication_map.erase(uid)
		save()
		return null
	elif not get_script_replication(script):
		var rep := ScriptReplication.new()
		_data.script_replication_map[uid] = rep
		if not rep.updated.is_connected(save):
			rep.updated.connect(save)
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
static func get_object_property_values(object: Node, peer: int) -> Array:
	# Calculate the property values for this script.
	var object_property_values := []
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		for config in sr.property_config:
			# We replicate all listed properties to the client initially.
			# Though, only be sure to replicate those that they care about.
			if not config.can_they_recv(object, peer):
				continue
			# Get the property value for this object.
			object_property_values.append(object.get(config.name))
	return object_property_values

## Applies a object's property values for the local peer.
static func apply_object_property_values(mp: MultiplayerRoot, object: Node, object_property_values: Array):
	var true_idx := -1
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		for config in sr.property_config:
			if not config.can_we_recv(mp, object):
				continue
			true_idx += 1
			object.set(config.name, object_property_values[true_idx])

#endregion

#region Method Cache API

## Gets a object's method name to its config.
static func object_method_to_config(object: Node, n: String) -> ReplicationMethodConfig:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr:
		assert(false)
		return null
	var cache := _get_object_method_to_config(base_sr, n)
	if cache:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config.
		var c := sr.get_method_config(n)
		if c:
			_put_object_method_to_config(base_sr, n, c)
			return c
	
	# Could not find.
	return null

## Converts a object's method name to an index.
static func object_method_to_idx(object: Node, c: ReplicationMethodConfig) -> int:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr:
		assert(false)
		return -1
	var cache := _get_object_method_to_idx(base_sr, c)
	if cache != -1:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	var current_idx := 0
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config in this SR.
		if sr.has_method_config(c):
			var result_idx := current_idx + sr.get_idx_from_method_config(c)
			_put_object_method_to_idx(base_sr, c, result_idx)
			return result_idx
		else:
			current_idx += sr.method_config.size()
	
	# Name was not found/defined.
	return -1

## Converts a object's method index back into its config.
static func object_idx_to_method(object: Node, idx: int) -> ReplicationMethodConfig:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr or idx < 0:
		assert(false)
		return null
	var cache := _get_object_idx_to_method(base_sr, idx)
	if cache:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config in this SR.
		var config_count := sr.method_config.size()
		if idx < config_count:
			var config := sr.get_method_config_from_idx(idx)
			_put_object_idx_to_method(base_sr, idx, config)
			return config
		else:
			idx -= config_count
			if idx < 0:
				break
	
	# Name was not found/defined.
	return null

static var _object_method_to_config_cache := {}

static func _put_object_method_to_config(sr: ScriptReplication, n: String, c: ReplicationMethodConfig):
	if sr not in _object_method_to_config_cache:
		_object_method_to_config_cache[sr] = {}
	_object_method_to_config_cache[sr][n] = c

static func _get_object_method_to_config(sr: ScriptReplication, n: String) -> ReplicationMethodConfig:
	if sr not in _object_method_to_config_cache:
		return null
	return _object_method_to_config_cache[sr].get(n, null)

static var _object_method_to_idx_cache := {}

static func _put_object_method_to_idx(sr: ScriptReplication, c: ReplicationMethodConfig, idx: int):
	if sr not in _object_method_to_idx_cache:
		_object_method_to_idx_cache[sr] = {}
	_object_method_to_idx_cache[sr][c] = idx

static func _get_object_method_to_idx(sr: ScriptReplication, c: ReplicationMethodConfig) -> int:
	if sr not in _object_method_to_idx_cache:
		return -1
	return _object_method_to_idx_cache[sr].get(c, -1)

static var _object_idx_to_method_cache := {}

static func _put_object_idx_to_method(sr: ScriptReplication, idx: int, c: ReplicationMethodConfig):
	if sr not in _object_idx_to_method_cache:
		_object_idx_to_method_cache[sr] = {}
	_object_idx_to_method_cache[sr][idx] = c

static func _get_object_idx_to_method(sr: ScriptReplication, idx: int) -> ReplicationMethodConfig:
	if sr not in _object_idx_to_method_cache:
		return null
	return _object_idx_to_method_cache[sr].get(idx, null)

#endregion

#region Property Cache API

## Gets a object's property name to its config.
static func object_property_to_config(object: Node, n: String) -> ReplicationPropertyConfig:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr:
		assert(false)
		return null
	var cache := _get_object_property_to_config(base_sr, n)
	if cache:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config.
		var c := sr.get_property_config(n)
		if c:
			_put_object_property_to_config(base_sr, n, c)
			return c
	
	# Could not find.
	return null

## Converts a object's property name to an index.
static func object_property_to_idx(object: Node, c: ReplicationPropertyConfig) -> int:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr:
		assert(false)
		return -1
	var cache := _get_object_property_to_idx(base_sr, c)
	if cache != -1:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	var current_idx := 0
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config in this SR.
		if sr.has_property_config(c):
			var result_idx := current_idx + sr.get_idx_from_property_config(c)
			_put_object_property_to_idx(base_sr, c, result_idx)
			return result_idx
		else:
			current_idx += sr.property_config.size()
	
	# Name was not found/defined.
	return -1

## Converts a object's property index back into its config.
static func object_idx_to_property(object: Node, idx: int) -> ReplicationPropertyConfig:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr or idx < 0:
		assert(false)
		return null
	var cache := _get_object_idx_to_property(base_sr, idx)
	if cache:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config in this SR.
		var config_count := sr.property_config.size()
		if idx < config_count:
			var config := sr.get_property_config_from_idx(idx)
			_put_object_idx_to_property(base_sr, idx, config)
			return config
		else:
			idx -= config_count
			if idx < 0:
				break
	
	# Name was not found/defined.
	return null

static var _object_property_to_config_cache := {}

static func _put_object_property_to_config(sr: ScriptReplication, n: String, c: ReplicationPropertyConfig):
	if sr not in _object_property_to_config_cache:
		_object_property_to_config_cache[sr] = {}
	_object_property_to_config_cache[sr][n] = c

static func _get_object_property_to_config(sr: ScriptReplication, n: String) -> ReplicationPropertyConfig:
	if sr not in _object_property_to_config_cache:
		return null
	return _object_property_to_config_cache[sr].get(n, null)

static var _object_property_to_idx_cache := {}

static func _put_object_property_to_idx(sr: ScriptReplication, c: ReplicationPropertyConfig, idx: int):
	if sr not in _object_property_to_idx_cache:
		_object_property_to_idx_cache[sr] = {}
	_object_property_to_idx_cache[sr][c] = idx

static func _get_object_property_to_idx(sr: ScriptReplication, c: ReplicationPropertyConfig) -> int:
	if sr not in _object_property_to_idx_cache:
		return -1
	return _object_property_to_idx_cache[sr].get(c, -1)

static var _object_idx_to_property_cache := {}

static func _put_object_idx_to_property(sr: ScriptReplication, idx: int, c: ReplicationPropertyConfig):
	if sr not in _object_idx_to_property_cache:
		_object_idx_to_property_cache[sr] = {}
	_object_idx_to_property_cache[sr][idx] = c

static func _get_object_idx_to_property(sr: ScriptReplication, idx: int) -> ReplicationPropertyConfig:
	if sr not in _object_idx_to_property_cache:
		return null
	return _object_idx_to_property_cache[sr].get(idx, null)

#endregion

#region Signal Cache API

## Gets a object's signal name to its config.
static func object_signal_to_config(object: Node, n: String) -> ReplicationSignalConfig:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr:
		assert(false)
		return null
	var cache := _get_object_signal_to_config(base_sr, n)
	if cache:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config.
		var c := sr.get_signal_config(n)
		if c:
			_put_object_signal_to_config(base_sr, n, c)
			return c
	
	# Could not find.
	return null

## Converts a object's signal name to an index.
static func object_signal_to_idx(object: Node, c: ReplicationSignalConfig) -> int:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr:
		assert(false)
		return -1
	var cache := _get_object_signal_to_idx(base_sr, c)
	if cache != -1:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	var current_idx := 0
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config in this SR.
		if sr.has_signal_config(c):
			var result_idx := current_idx + sr.get_idx_from_signal_config(c)
			_put_object_signal_to_idx(base_sr, c, result_idx)
			return result_idx
		else:
			current_idx += sr.signal_config.size()
	
	# Name was not found/defined.
	return -1

## Converts a object's signal index back into its config.
static func object_idx_to_signal(object: Node, idx: int) -> ReplicationSignalConfig:
	# Check if cached.
	var base_sr := get_script_replication(object.get_script())
	if not base_sr or idx < 0:
		assert(false)
		return null
	var cache := _get_object_idx_to_signal(base_sr, idx)
	if cache:
		return cache
	
	# Calculate the SR for this parent depth.
	var parent_depth := -1
	while true:
		parent_depth += 1
		var sr := get_script_replication(object.get_script(), parent_depth)
		if not sr:
			break
		
		# Look for the config in this SR.
		var config_count := sr.signal_config.size()
		if idx < config_count:
			var config := sr.get_signal_config_from_idx(idx)
			_put_object_idx_to_signal(base_sr, idx, config)
			return config
		else:
			idx -= config_count
			if idx < 0:
				break
	
	# Name was not found/defined.
	return null

static var _object_signal_to_config_cache := {}

static func _put_object_signal_to_config(sr: ScriptReplication, n: String, c: ReplicationSignalConfig):
	if sr not in _object_signal_to_config_cache:
		_object_signal_to_config_cache[sr] = {}
	_object_signal_to_config_cache[sr][n] = c

static func _get_object_signal_to_config(sr: ScriptReplication, n: String) -> ReplicationSignalConfig:
	if sr not in _object_signal_to_config_cache:
		return null
	return _object_signal_to_config_cache[sr].get(n, null)

static var _object_signal_to_idx_cache := {}

static func _put_object_signal_to_idx(sr: ScriptReplication, c: ReplicationSignalConfig, idx: int):
	if sr not in _object_signal_to_idx_cache:
		_object_signal_to_idx_cache[sr] = {}
	_object_signal_to_idx_cache[sr][c] = idx

static func _get_object_signal_to_idx(sr: ScriptReplication, c: ReplicationSignalConfig) -> int:
	if sr not in _object_signal_to_idx_cache:
		return -1
	return _object_signal_to_idx_cache[sr].get(c, -1)

static var _object_idx_to_signal_cache := {}

static func _put_object_idx_to_signal(sr: ScriptReplication, idx: int, c: ReplicationSignalConfig):
	if sr not in _object_idx_to_signal_cache:
		_object_idx_to_signal_cache[sr] = {}
	_object_idx_to_signal_cache[sr][idx] = c

static func _get_object_idx_to_signal(sr: ScriptReplication, idx: int) -> ReplicationSignalConfig:
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE_READ)
	f.store_string(JSON.stringify(serialize(), "\t"))

static func _load() -> ReplicationData:
	if not FileAccess.file_exists(SAVE_PATH):
		return ReplicationData.new()
	return deserialize(JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)))

static func serialize() -> Dictionary:
	var d: Dictionary = {}
	for k: int in _data.script_replication_map:
		var rep: ScriptReplication = _data.script_replication_map[k]
		d[k] = rep.serialize(k)
	return d

static func deserialize(d: Dictionary) -> ReplicationData:
	var data := ReplicationData.new()
	for k in d:
		data.script_replication_map[int(k)] = ScriptReplication.deserialize(d[k])
	return data

#endregion

#region Static util

# Apparently, these functions are expensive, so I'm adding caches for them.
static var _uid_to_path_cache: Dictionary[int, String] = {}
static var _path_to_uid_cache: Dictionary[String, int] = {}

## converts uid => path (returns "" if doesnt exist)
static func uid_to_path(uid: int) -> String:
	if uid in _uid_to_path_cache:
		return _uid_to_path_cache[uid]
	var path := ""
	if ResourceUID.has_id(uid):
		path = ResourceUID.get_id_path(uid)
	_uid_to_path_cache[uid] = path
	return path

## converts path => uid (returns -1 if doesnt exist)
static func path_to_uid(path: String) -> int:
	if path in _path_to_uid_cache:
		return _path_to_uid_cache[path]
	var uid := ResourceLoader.get_resource_uid(path)
	_path_to_uid_cache[path] = uid
	return uid

#endregion
