@tool
extends Object
class_name ReplicationCacheManager

const CACHE_PATH: String = "res://addons/godaemon_multiplayer/cache/replication_storage.tres"
const CACHE_STORAGE := preload("res://addons/godaemon_multiplayer/cache/replication_storage_resource.gd")

static var cache_storage: CACHE_STORAGE = null

static func _static_init() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		cache_storage = ResourceLoader.load(CACHE_PATH)
	else:
		cache_storage = CACHE_STORAGE.new()

	if Engine.is_editor_hint():
		# Clean up any old lingering entries that may no longer be valid.
		var any_changed: bool = false
		for file_path: String in cache_storage.cache_dict.keys().duplicate():
			if not FileAccess.file_exists(file_path):
				cache_storage.cache_dict.erase(file_path)
				any_changed = true

		if any_changed:
			cache_storage.save()

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
