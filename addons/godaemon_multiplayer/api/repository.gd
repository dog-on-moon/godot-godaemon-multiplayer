extends RefCounted
## A repository of unique node IDs for the GodaemonMultiplayerAPI.
## Nodes must be registered here on client and server to use RPCs.

## The max size of the node repository, in bits.
## Turning this up will support more nodes on the server/client.
const MAX_BITS := 32
const MAX_BYTES := MAX_BITS / 8
const MAX_ID := 2 ** MAX_BITS

var api: GodaemonMultiplayerAPI

func _init(_api: GodaemonMultiplayerAPI):
	api = _api

func cleanup():
	node_to_id = {}
	id_to_node = {}
	api = null

var _current_id := 0

var node_to_id := {}
var id_to_node := {}

## Adds a Node to the repository. Can specify a node_id. Returns the set id.
func add_node(node: Node, node_id := -1) -> int:
	assert(node not in node_to_id)
	assert(node_to_id.size() < MAX_ID, "Repository overflow.")
	if node_id == -1:
		while _current_id in id_to_node:
			_current_id += 1
			if _current_id >= MAX_ID:
				_current_id = 0
		node_id = _current_id
	else:
		assert(node_id not in node_to_id, "Node IDs are stomping.")
	# print('[%s] adding %s with ID=%s' % [api.mp.name, node, node_id])
	node_to_id[node] = node_id
	id_to_node[node_id] = node
	node.tree_exited.connect(remove_node_id.bind(node_id), CONNECT_ONE_SHOT + CONNECT_DEFERRED)
	return node_id

## Removes a Node from the repository.
func remove_node(node: Node):
	assert(node in node_to_id)
	id_to_node.erase(node_to_id[node])
	node_to_id.erase(node)

func remove_node_id(id: int):
	assert(id in id_to_node)
	node_to_id.erase(id_to_node[id])
	id_to_node.erase(id)

## Returns the node based on an ID in the repository. Returns null if not found.
func get_node(id: int) -> Node:
	return id_to_node.get(id, null)

## Returns the ID of a node in the repository. Returns -1 if not found.
func get_id(node: Node) -> int:
	return node_to_id.get(node, -1)
