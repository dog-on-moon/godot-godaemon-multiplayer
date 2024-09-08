@tool
extends Object
class_name ReplicationCacheManager

const REPCO = preload("res://addons/godaemon_multiplayer/services/replication/constants.gd")
const CACHE_PATH: String = "res://addons/godaemon_multiplayer/cache/replication_storage.tres"
const CACHE_STORAGE := preload("res://addons/godaemon_multiplayer/cache/replication_storage_resource.gd")
const PATH_LOADER = preload("res://addons/godaemon_multiplayer/util/path_loader.gd")

static var cache_storage: CACHE_STORAGE = null

static func update_cache(initial := false):
	if initial:
		# Load cache storage resource.
		if FileAccess.file_exists(CACHE_PATH):
			cache_storage = ResourceLoader.load(CACHE_PATH)
		else:
			cache_storage = CACHE_STORAGE.new()
	
	var any_changed: bool = false
	
	# Clean up old IDs that don't exist anymore.
	for file_path: String in cache_storage.cache_dict.keys():
		if not FileAccess.file_exists(file_path):
			cache_storage.remove_scene_from_cache(file_path)
			any_changed = true
			# print('Removed %s from cache' % file_path)
	
	# If there's been any changes, rescan scenes for IDs and save.
	if any_changed or initial:
		var project_scene_paths := PATH_LOADER.load_filepaths('res://', '.tscn')
		for scene_file_path in project_scene_paths:
			if scene_file_path in cache_storage.cache_dict:
				continue
			var scene: PackedScene = load(scene_file_path)
			var scene_state := scene.get_state()
			for prop_idx in scene_state.get_node_property_count(0):
				var prop_name := scene_state.get_node_property_name(0, prop_idx)
				var prop_value := scene_state.get_node_property_value(0, prop_idx)
				if prop_name == StringName("metadata/%s" % REPCO.META_REPLICATE_SCENE):
					cache_storage.add_scene_to_cache(scene_file_path)
					# print('Added %s to cache' % scene_file_path)
					break
		
		cache_storage.save()
	
	if initial:
		EditorInterface.get_resource_filesystem().scan.call_deferred()

## Adds a node to the cache storage and saves
static func add_node_to_storage(node: Node) -> void:
	cache_storage.add_node_to_cache(node)

## Removes a node from the cache storage and saves
static func remove_node_from_storage(node: Node) -> void:
	cache_storage.remove_node_from_cache(node)

static func get_index(scene_file_path: String) -> int:
	return cache_storage.cache_dict.get(scene_file_path, -1)

static func get_scene_file_path(index: int) -> String:
	return cache_storage.rep_id_to_scene_path.get(index, '')
