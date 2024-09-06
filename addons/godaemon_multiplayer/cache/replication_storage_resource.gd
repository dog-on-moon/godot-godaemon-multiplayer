@tool
extends Resource
## Global storage of cache data for replication

const NODE_CACHE := preload("res://addons/godaemon_multiplayer/cache/replication_node_cache.gd")
const SAVE_PATH: String = "res://addons/godaemon_multiplayer/cache/replication_storage.tres"

@export var cache_dict: Dictionary = {}:
	set(x):
		cache_dict = x
		# Initialize reversed dict when resource is loaded
		for scene_path: String in cache_dict.keys():
			var cache: NODE_CACHE = cache_dict[scene_path]
			rep_id_to_scene_path[cache.rep_id] = scene_path

var rep_id_to_scene_path: Dictionary = {}

## Adds a node to the cache dict and saves
func add_node_to_cache(node: Node) -> void:
	var node_path: String = get_node_scene_file_path(node)
	if node_path not in cache_dict:
		var next_rep_id: int = get_next_rep_id()
		var new_node_cache: NODE_CACHE = NODE_CACHE.new(next_rep_id)
		cache_dict[node_path] = new_node_cache
		rep_id_to_scene_path[next_rep_id] = node_path
		save()

## Adds a node's property to the relevant cache dict and saves
func add_prop_to_node_cache(node: Node, property: String) -> void:
	var node_path: String = get_node_scene_file_path(node)
	if cache_dict.get(node_path):
		var node_cache: NODE_CACHE = cache_dict[node_path]
		node_cache.add_prop_cache(node, property)
		save()

## Removes a node from the cache dict and saves
func remove_node_from_cache(node: Node) -> void:
	var node_path: String = get_node_scene_file_path(node)
	if node_path in cache_dict:
		var cache_entry: NODE_CACHE = get_cache_from_node(node)
		if cache_entry.rep_id in rep_id_to_scene_path:
			rep_id_to_scene_path.erase(cache_entry.rep_id)
		cache_dict.erase(node_path)
		save()

## Removes a node's property from the relevant cache dict and saves
func remove_prop_from_node_cache(node: Node, property: String) -> void:
	var node_path: String = get_node_scene_file_path(node)
	if cache_dict.get(node_path):
		var node_cache: NODE_CACHE = cache_dict[node_path]
		node_cache.remove_prop_cache(node, property)
		save()

## Grabs the relevant Node Cache for the passed node
func get_cache_from_node(node: Node) -> NODE_CACHE:
	return cache_dict.get(get_node_scene_file_path(node))

## Saves storage to disk
func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)
	take_over_path(SAVE_PATH)

## Gets the next valid property replication ID
func get_next_rep_id() -> int:
	var ids: Array[int] = []
	for entry: NODE_CACHE in cache_dict.values():
		ids.append(entry.rep_id)
	var curr_max = ids.max()
	if curr_max == null:
		curr_max = -1
	return curr_max + 1

func get_node_scene_file_path(node: Node) -> String:
	return node.scene_file_path if node.scene_file_path else node.owner.scene_file_path
