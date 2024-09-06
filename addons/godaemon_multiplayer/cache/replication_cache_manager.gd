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

## Adds a node to the cache storage and saves
static func add_node_to_storage(node: Node) -> void:
	cache_storage.add_node_to_cache(node)

## Adds a property to the given node cache and saves
static func add_prop_to_node_storage(node: Node, property: String) -> void:
	cache_storage.add_prop_to_node_cache(node, property)

## Removes a node from the cache storage and saves
static func remove_node_from_storage(node: Node) -> void:
	cache_storage.remove_node_from_cache(node)

## Removes a property from the given node cache and saves
static func remove_prop_from_node_storage(node: Node, property: String) -> void:
	cache_storage.remove_prop_from_node_cache(node, property)
