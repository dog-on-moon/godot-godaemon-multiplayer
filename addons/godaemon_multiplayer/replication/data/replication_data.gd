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

## Returns a script's replication data.
## Returns null if it does not exist.
static func get_script_replication(script: Script) -> ScriptReplication:
	var uid := path_to_uid(script.resource_path)
	if uid == -1:
		print('script %s has no uid?' % script.resource_path)
		return null
	return _data.script_replication_map.get(uid, null)

## Toggles a script's replication.
static func toggle_script_replication(script: Script, mode: bool) -> ScriptReplication:
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

#region Static util

## converts uid => path (returns "" if doesnt exist)
static func uid_to_path(uid: int) -> String:
	if not ResourceUID.has_id(uid):
		return ""
	return ResourceUID.get_id_path(uid)

## converts path => uid (returns -1 if doesnt exist)
static func path_to_uid(path: String) -> int:
	return ResourceLoader.get_resource_uid(path)

#endregion
