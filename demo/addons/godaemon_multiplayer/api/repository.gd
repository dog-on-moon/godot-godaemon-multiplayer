extends RefCounted
## A repository of unique object IDs for the GodaemonMultiplayerAPI.
## Objects must be registered here on client and server to use RPCs.

## The max size of the object repository, in bits.
## Turning this up will support more objects on the server/client.
const MAX_BITS := 32
const MAX_BYTES := MAX_BITS / 8
const MAX_ID := 2 ** MAX_BITS

var api: GodaemonMultiplayerAPI

func _init(_api: GodaemonMultiplayerAPI):
	api = _api

func cleanup():
	object_to_id = {}
	id_to_object = {}
	api = null

var _current_id := 0

var object_to_id := {}
var id_to_object := {}

## Adds a Object to the repository. Can specify a object_id. Returns the set id.
func add_object(object: Object, object_id := -1) -> int:
	assert(object not in object_to_id)
	assert(object_to_id.size() < MAX_ID, "Repository overflow.")
	if object_id == -1:
		while _current_id in id_to_object:
			_current_id += 1
			if _current_id >= MAX_ID:
				_current_id = 0
		object_id = _current_id
	else:
		assert(object_id not in object_to_id, "Object IDs are stomping.")
	# print('[%s] adding %s with ID=%s' % [api.mp.name, object, object_id])
	object_to_id[object] = object_id
	id_to_object[object_id] = object
	return object_id

## Removes a Object from the repository.
func remove_object(object: Object):
	assert(object in object_to_id)
	id_to_object.erase(object_to_id[object])
	object_to_id.erase(object)

func remove_object_id(id: int):
	assert(id in id_to_object)
	object_to_id.erase(id_to_object[id])
	id_to_object.erase(id)

## Returns the object based on an ID in the repository. Returns null if not found.
func get_object(id: int) -> Object:
	return id_to_object.get(id, null)

## Returns the ID of a object in the repository. Returns -1 if not found.
func get_id(object: Object) -> int:
	return object_to_id.get(object, -1)

## Returns whether or not a given object is replicated.
func is_replicated(object: Object) -> bool:
	return get_id(object) != -1
