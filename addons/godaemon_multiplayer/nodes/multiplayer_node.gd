@tool
extends Node
class_name MultiplayerNode
## Contains shared information for ClientNodes and ServerNodes.

#region Exports

## Attempts to endlessly multiconnect when the node is added.
@export var multiconnect_on_ready := true

@onready var __multiconnect_on_ready = _multiconnect_on_ready.call()
func _multiconnect_on_ready():
	if Engine.is_editor_hint():
		return
	start_multi_connect()

#endregion

#region Signals

## Emitted when connection has successfully established with a ClientNode.
signal connection_success

## Emitted when connection failed with a ClientNode.
signal connection_failed(state: ConnectionState)

## Emitted when the server shuts down.
signal server_disconnected

## Emitted when another peer has connected to the server.
signal peer_connected(peer: int)

## Emitted when a peer has disconnected from the server.
signal peer_disconnected(peer: int)

#endregion

#region Properties

## Possible connection states.
enum ConnectionState {
	DISCONNECTED,    ## No connection.
	WAITING,         ## We are waiting to begin authentication.
	AUTHENTICATING,  ## [client] Currently authenticating with a ServerNode.
	TIMEOUT,         ## We timed out before connecting.
	AUTH_TIMEOUT,    ## [client] We failed to authenticate.
	CONNECTED,       ## Connected.
}

## The current connection state.
var connection_state := ConnectionState.DISCONNECTED

## Returns the name of a connection state.
static func get_connection_state_name(state: ConnectionState) -> String:
	for n in ConnectionState:
		if ConnectionState[n] == state:
			return n
	push_error("MultiplayerNode.get_connection_state_name does not know %s" % state)
	return ""

var zone_service: ZoneService

#endregion

#region Connection

## Attempts a connection. Returns true on success, false on failure.
func start_connection() -> bool:
	# unimplemented
	assert(false)
	return false

#region Multi-Connecting

var _currently_multi_connecting := false

## Attempts multiple reconnects to the server.
## Set attempts to -1 for unlimited attempts.
## Can be cancelled with ServerNode.cancel_multiple_connects.
func start_multi_connect(attempts := -1) -> bool:
	assert(connection_state == ConnectionState.DISCONNECTED)
	_currently_multi_connecting = true
	while attempts != 0:
		if await start_connection():
			_currently_multi_connecting = false
			return true
		if not _currently_multi_connecting:
			return false
		attempts -= 1
	_currently_multi_connecting = false
	return false

## Cancels multi-connecting once the current connection attempt is complete.
func end_multi_connect():
	if not _currently_multi_connecting:
		push_warning("MultiplayerNode.end_multi_connect was not actively multi-connecting")
	_currently_multi_connecting = false

#endregion

## Closes the connection.
func end_connection() -> bool:
	# unimplemented
	assert(false)
	return false

#endregion

#region Services

var services: Array[Node] = []
var service_cache := {}

@onready var __setup_service_signals = _setup_service_signals.call()
func _setup_service_signals():
	if Engine.is_editor_hint():
		return
	connection_success.connect(_setup_services)
	server_disconnected.connect(_cleanup_services)

func _setup_services():
	_cleanup_services()
	var nodes_to_add: Array[Node] = []
	for script: Script in get_service_scripts():
		if not script.get_global_name():
			push_error("MultiplayerNode: service '%s' is missing script global name" % script.resource_path)
			continue
		var n = script.new()
		if n is not Node:
			push_error("MultiplayerNode: service '%s' is not a node" % script.resource_path)
			continue
		services.append(n)
		service_cache[script] = n
		n.name = script.get_global_name()
		nodes_to_add.append(n)
	for packed_scene: PackedScene in get_service_scenes():
		var n := packed_scene.instantiate()
		if not n.get_script():
			push_error("MultiplayerNode: service '%s' is missing a script" % packed_scene.resource_path)
			continue
		if not n.get_script().get_global_name():
			push_error("MultiplayerNode: service '%s' is missing script global name" % n.get_script().resource_path)
			continue
		services.append(n)
		service_cache[n.get_script()] = n
		n.name = n.get_script().get_global_name()
		nodes_to_add.append(n)
	
	# this add children shenanigans is a bit tragic,
	# but it basically calls _enter_tree on all services (in reverse)
	# and then calls _ready on all services (in order)
	nodes_to_add.reverse()
	_add_children(nodes_to_add)

func _add_children(nodes: Array[Node]):
	if not nodes:
		return
	var n := nodes.pop_at(0)
	n.tree_entered.connect(_add_children.bind(nodes), CONNECT_ONE_SHOT)
	add_child(n)
	move_child(n, -1)

func _cleanup_services():
	for service in services:
		service.queue_free()
	services = []
	service_cache = {}

## Returns a service by script reference.
func get_service(t: Script) -> Node:
	return service_cache.get(t, null)

## Determines if a service exists on the MultiplayerNode.
func has_service(t: Script) -> bool:
	return t in service_cache

## Gets all service scripts.
func get_service_scripts() -> Array[Script]:
	return []

## Gets all service scenes.
func get_service_scenes() -> Array[PackedScene]:
	return []

#endregion

#region Getters

## Returns true if the MultiplayerNode is being ran as a client.
func is_client() -> bool:
	return false

## Returns true if the MultiplayerNode is being ran as a server.
func is_server() -> bool:
	return false

## Returns true if the Zone is being ran as a local scene.
## This is useful for testing and developing areas.
func is_local_dev() -> bool:
	return self == get_tree().current_scene

## Finds the MultiplayerNode associated with a given Node.
static func fetch(node: Node) -> MultiplayerNode:
	var tree := node.get_tree()
	if not tree:
		return null
	while node is not MultiplayerNode and node != tree.root:
		node = node.get_parent()
	if node is MultiplayerNode:
		return node
	return null

#endregion
