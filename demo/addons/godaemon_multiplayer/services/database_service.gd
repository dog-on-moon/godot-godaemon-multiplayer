extends ServiceBase
class_name DatabaseService
## An optional service for attaching database read/writes to a replicated script.

## Controls how long database autosaving takes.
const AUTOSAVE_DURATION := 60.0

## An implementation of a database beneath the service API.
## Must be set externally before this service can be used.
var db: DBBase:
	set(x):
		if db:
			db.service = null
		db = x
		if db:
			db.service = self

## A map of all objects currently tracked by the DatabaseService.
var _tracked_objects: Dictionary[Object, Array] = {}

var _autosave_tween: Tween

func _ready() -> void:
	if mp.is_server():
		_autosave_tween = create_tween()
		_autosave_tween.tween_interval(AUTOSAVE_DURATION)
		_autosave_tween.tween_callback(_autosave)
		_autosave_tween.set_loops()

signal _track_complete
var _track_locked := false

## Tracks an object in the database.
func track_object(object: Object, collection: String, key: String):
	# API safety barrierz
	if not _api_safety(): return
	if object is Node:
		if object.is_inside_tree() or object.is_node_ready():
			push_warning("DatabaseService.track_object called on a node inside the tree.\nPreferably this should be called before the node is added to the tree.")
	if object in _tracked_objects:
		assert(false, "Cannot re-track already tracked object")
		return
	
	# Barrier to prevent multiple concurrent tracks
	if _track_locked:
		await _track_complete
	_track_locked = true
	
	# Begin object tracking.
	_tracked_objects[object] = [collection, key]
	object.set_emit_freeing(true)
	object.freeing.connect(untrack_object.bind(object))
	
	# Apply stored database values.
	var current_values := await db.read(collection, key)
	apply_object_database_values(object, current_values)
	
	# Immediately re-save stored values.
	await save_object(object)
	
	_track_locked = false
	_track_complete.emit()

## Untracks an object from the DatabaseService.
func untrack_object(object: Object):
	if not _api_safety(): return
	elif object not in _tracked_objects: return
	save_object(object)
	object.freeing.disconnect(untrack_object.bind(object))
	_tracked_objects.erase(object)

## Saves an object in the database.
## Can be called optionally manually.
func save_object(object: Object):
	if not _api_safety(): return
	elif object not in _tracked_objects:
		assert(false, "Cannot save untracked object")
		return
	var values := get_object_database_values(object)
	var data := _tracked_objects[object]
	await db.write(data[0], data[1], values)

var _autosaving := false

## Autosave all currently tracked objects.
func _autosave():
	if _autosaving: return
	_autosaving = true
	for obj in _tracked_objects:
		await save_object(obj)
		await get_tree().process_frame
	_autosaving = false

## Harvests a object's database values.
static func get_object_database_values(object: Object) -> Dictionary[String, Variant]:
	var db_values: Dictionary[String, Variant] = {}
	for sr in ReplicationData.get_all_script_replications(object.get_script()):
		for config in sr.property_config:
			if config.get_database():
				db_values[config.name] = object.get(config.name)
	return db_values

## Applies a object's database values.
static func apply_object_database_values(object: Object, database_values: Dictionary[String, Variant]):
	for key in database_values:
		object.set(key, database_values[key])

func _api_safety() -> bool:
	if not mp:
		return false
	elif mp.is_client():
		assert(false, "DatabaseService can only be used on the server.")
		return false
	elif not db:
		assert(false, "DatabaseService.db is not defined.")
		return false
	return true
