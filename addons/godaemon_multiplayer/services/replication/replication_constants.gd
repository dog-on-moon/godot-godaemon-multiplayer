## Constants for replication. Yay

const META_SYNC_PROPERTIES := &"_mp"
const META_REPLICATE_SCENE := &"_r"
const META_OWNER := &"_o"

enum PeerFilter {
	SERVER = 0,
	OWNER_SERVER = 1,
	CLIENTS_SERVER = 2
}

const PeerFilterBitfieldToName := {
	PeerFilter.SERVER: "Server Only",
	PeerFilter.OWNER_SERVER: "Owner + Server",
	PeerFilter.CLIENTS_SERVER: "Clients + Server",
}

const DEFAULT_SEND_FILTER := PeerFilter.SERVER
const DEFAULT_RECV_FILTER := PeerFilter.CLIENTS_SERVER
const DEFAULT_SYNC_INTERP := false
const DEFAULT_SYNC_RELIABLE := true

static func editor_filter_to_real_filter(editor: int) -> int:
	return PeerFilterBitfieldToName.keys()[editor]

static func real_filter_to_editor_filter(real: int) -> int:
	return PeerFilterBitfieldToName.keys().find(real)

## Sets the replicated property of a node.
static func set_replicated_property(object: Node, property_path: NodePath, send: int, recv: int, reliable: bool, interp: bool):
	const key_name := META_SYNC_PROPERTIES
	if not object.has_meta(key_name):
		object.set_meta(key_name, {})
	var property_dict: Dictionary = object.get_meta(key_name)
	property_dict[property_path] = [send, recv, reliable, interp]
	ReplicationCacheManager.add_node_to_storage(object)
	ReplicationCacheManager.add_prop_to_node_storage(object, property_path)
	return true

## Gets the replicated property of a node.
## If unspecified, returns an empty Array.
static func get_replicated_property(object: Node, property_path: NodePath) -> Array:
	return object.get_meta(META_SYNC_PROPERTIES, {}).get(property_path, [])

## Removes the replicated property from the node.
static func remove_replicated_property(object: Node, property_path: NodePath):
	var property_dict := object.get_meta(META_SYNC_PROPERTIES, {})
	property_dict.erase(property_path)
	if not property_dict:
		object.remove_meta(META_SYNC_PROPERTIES)

	ReplicationCacheManager.remove_prop_from_node_storage(object, property_path)

## Returns the replicated property dict of a node.
static func get_replicated_property_dict(object: Node) -> Dictionary:
	return object.get_meta(META_SYNC_PROPERTIES, {})

## Returns all nodes under a root that require replication.
static func get_replicated_nodes(root: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	_harvest_replicated_nodes(root, nodes)
	return nodes

static func _harvest_replicated_nodes(root: Node, nodes: Array[Node]):
	if root.has_meta(META_SYNC_PROPERTIES):
		nodes.append(root)
	for child in root.get_children():
		_harvest_replicated_nodes(child, nodes)

## Returns the owner of a Node.
static func get_node_owner(node: Node) -> int:
	return node.get_meta(META_OWNER, 1)
