@tool
extends Resource
## Global storage of cache data for replication

## The max size of the scene repository, in bits.
## Turning this up will support more scenes that can be replicated.
const MAX_BITS := 16
const MAX_BYTES := MAX_BITS / 8
const MAX_ID := 2 ** MAX_BITS

const UTIL := preload("res://addons/godaemon_multiplayer/util/util.gd")
const SAVE_PATH: String = "res://addons/godaemon_multiplayer/cache/replication_storage.tres"

@export var cache_dict: Dictionary = {}:
	set(x):
		cache_dict = x
		rep_id_to_scene_path = UTIL.invert_dictionary(cache_dict)

var rep_id_to_scene_path: Dictionary = {}

## Adds a node to the cache dict and saves
func add_node_to_cache(node: Node) -> void:
	add_scene_to_cache(get_node_scene_file_path(node))

## Removes a node from the cache dict and saves
func remove_node_from_cache(node: Node) -> void:
	remove_scene_from_cache(get_node_scene_file_path(node))

func add_scene_to_cache(scene_file_path: String):
	if scene_file_path not in cache_dict:
		var next_rep_id: int = get_next_rep_id()
		if next_rep_id >= MAX_ID:
			push_error("ReplicationStorageResource is full. Please turn up ReplicationStorageResource.MAX_BITS to %s" % (MAX_BITS * 2))
		cache_dict[scene_file_path] = next_rep_id
		rep_id_to_scene_path[next_rep_id] = scene_file_path
		save()

func remove_scene_from_cache(scene_file_path: String):
	if scene_file_path in cache_dict:
		var rep_id: int = cache_dict[scene_file_path]
		if rep_id in rep_id_to_scene_path:
			rep_id_to_scene_path.erase(rep_id)
		cache_dict.erase(scene_file_path)
		save()

## Saves storage to disk
func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)
	take_over_path(SAVE_PATH)

## Gets the next valid property replication ID
func get_next_rep_id() -> int:
	var idx := 0
	while idx in rep_id_to_scene_path:
		idx += 1
	return idx

func get_node_scene_file_path(node: Node) -> String:
	return node.scene_file_path if node.scene_file_path else node.owner.scene_file_path
