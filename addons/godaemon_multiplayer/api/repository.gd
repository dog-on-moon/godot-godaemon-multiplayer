extends RefCounted
## A repository of unique node IDs for the GodaemonMultiplayerAPI.
## Nodes must be registered here on client and server to use RPCs.

## Returns the max bytes of the repository.
## Turning this up will support more tracked nodes on the server/client.
const MAX_BITS := 16
const MAX_ID := 2 ** MAX_BITS

static var _current_id := 0

var api: GodaemonMultiplayerAPI

func _init(_api: GodaemonMultiplayerAPI):
	api = _api

func cleanup():
	node_to_id = {}
	id_to_node = {}
	api = null

var node_to_id := {}
var id_to_node := {}

## Adds a Node to the repository. Can specify a node_id. Returns the set id.
func add_node(node: Node, node_id := -1) -> int:
	if node_id == -1:
		node_id = 0
		while node_id in id_to_node and node_id < MAX_ID:
			node_id += 1
	else:
		assert(node_id not in node_to_id, "Node IDs are stomping.")
	assert(node_id < MAX_ID, "Repository overflow.")
	node_to_id[node] = node_id
	id_to_node[node_id] = node
	return node_id

## Returns the node based on an ID in the repository. Returns null if not found.
func get_node(id: int) -> Node:
	return id_to_node.get(id, null)

## Returns the ID of a node in the repository. Returns -1 if not found.
func get_id(node: Node) -> int:
	return node_to_id.get(node, -1)
