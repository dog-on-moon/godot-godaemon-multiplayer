@tool
@icon("res://addons/godaemon_multiplayer/icons/SignalsAndGroups.svg")
extends Node
class_name MultiplayerRoot
## Base class for ClientRoot and ServerRoot.

const MAX_ENET_CHANNELS := 253

#region Exports

## Attempts to endlessly multiconnect when the node is added.
## Note that it is deferred.
@export var multiconnect_on_ready := true

@onready var __multiconnect_on_ready = _multiconnect_on_ready.call()
func _multiconnect_on_ready():
	if Engine.is_editor_hint() or not multiconnect_on_ready:
		return
	start_multi_connect.call_deferred()

## Client/Server configuration that should be the same between a ClientRoot and ServerRoot.
@export var configuration: MultiplayerConfig:
	set(x):
		if configuration:
			configuration.property_list_changed.disconnect(notify_property_list_changed)
			configuration.property_list_changed.disconnect(update_configuration_warnings)
		configuration = x
		if configuration:
			configuration.property_list_changed.connect(notify_property_list_changed)
			configuration.property_list_changed.connect(update_configuration_warnings)
		notify_property_list_changed()
		update_configuration_warnings()

@onready var __setup_timeout_handler = _setup_timeout_handler.call()
func _setup_timeout_handler():
	if Engine.is_editor_hint():
		return
	peer_connected.connect(
		func (p: int):
			var packet_peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(p)
			var unlimited_time := configuration.enable_peer_timeout
			if OS.has_feature("editor"):
				unlimited_time = configuration.enable_dev_peer_timeout
			if not unlimited_time:
				packet_peer.set_timeout(configuration.peer_timeout * 1000.0, configuration.peer_timeout_minimum * 1000.0, configuration.peer_timeout_maximum * 1000.0)
			else:
				packet_peer.set_timeout(configuration.peer_timeout * 1000.0, 3600.0 * 1000.0, 3600.0 * 1000.0)
	)

#endregion

#region Signals

## Emitted when connection has successfully established with a ClientRoot.
signal connection_success

## Emitted when connection failed with a ClientRoot.
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
	AUTHENTICATING,  ## [client] Currently authenticating with a ServerRoot.
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
	push_error("MultiplayerRoot.get_connection_state_name does not know %s" % state)
	return ""

var api: GodaemonMultiplayerAPI:
	get: return multiplayer

var local_peer: int:
	get: return api.get_unique_id()

var remote_peer: int:
	get: return api.get_remote_sender_id()

var authenticator: PeerAuthenticator

func setup_peer_authenticator():
	assert(api is GodaemonMultiplayerAPI)
	if not authenticator:
		authenticator = PeerAuthenticator.new()
		authenticator.api = api
		authenticator.mp = self

func cleanup_peer_authenticator():
	authenticator = null

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
## Can be cancelled with ServerRoot.cancel_multiple_connects.
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
		push_warning("MultiplayerRoot.end_multi_connect was not actively multi-connecting")
	_currently_multi_connecting = false

#endregion

## Closes the connection.
func end_connection() -> bool:
	# unimplemented
	assert(false)
	return false

#endregion

#region Services

var services: Array[ServiceBase] = []
var service_cache := {}
var service_name_cache := {}

var service_channel_start := {}
var service_channel_count := 0

@onready var __setup_service_signals = _setup_service_signals.call()
func _setup_service_signals():
	if Engine.is_editor_hint():
		return
	_determine_service_channels()
	connection_success.connect(_setup_services)
	server_disconnected.connect(_cleanup_services)

func _determine_service_channels():
	service_channel_count = 0
	for script: Script in configuration.services:
		if not script.get_global_name():
			continue
		var n = script.new()
		if n is not ServiceBase:
			continue
		var service: ServiceBase = n
		var service_channels = service.get_reserved_channels()
		if service_channels != null:
			service_channel_start[script.get_global_name()] = service_channel_count
			service_channel_count += service_channels
		n.queue_free()

func _setup_services():
	api.repository.add_node(self)
	
	_cleanup_services()
	var nodes_to_add: Array[ServiceBase] = []
	for script: Script in configuration.services:
		if not script.get_global_name():
			push_error("MultiplayerRoot: service '%s' is missing script global name" % script.resource_path)
			continue
		var n = script.new()
		if n is not ServiceBase:
			push_error("MultiplayerRoot: service '%s' is not a ServiceBase" % script.resource_path)
			continue
		services.append(n)
		service_cache[script] = n
		service_name_cache[script.get_global_name()] = n
		n.name = script.get_global_name()
		n.mp = self
		api.repository.add_node(n)
		nodes_to_add.append(n)
	
	# this add children shenanigans is a bit tragic,
	# but it basically calls _enter_tree on all services (in reverse)
	# and then calls _ready on all services (in order)
	nodes_to_add.reverse()
	_add_services(nodes_to_add)

func _add_services(nodes: Array[ServiceBase]):
	if not nodes:
		return
	var n := nodes.pop_at(0)
	n.tree_entered.connect(_add_services.bind(nodes), CONNECT_ONE_SHOT)
	add_child(n)
	n._setup()
	move_child(n, -1)

func _cleanup_services():
	for service in services:
		service.queue_free()
	services = []
	service_cache = {}
	service_name_cache = {}

## Returns a service by script reference.
func get_service(t: Script, required := true) -> ServiceBase:
	if required:
		assert(t in service_cache, "MultiplayerConfig missing dependent service: %s" % t.get_global_name())
	return service_cache.get(t, null)

## Determines if a service exists on the MultiplayerRoot.
func has_service(t: Script) -> bool:
	return t in service_cache

## Gets the starting index of a service's channels.
func get_service_channel_start(service: ServiceBase) -> int:
	var key: StringName = service.get_script().get_global_name()
	if key not in service_channel_start:
		return 0
	return service_channel_start[key] + configuration.channel_count + 1

#endregion

#region Getters

## Returns true if the MultiplayerRoot is being ran as a client.
func is_client() -> bool:
	return api.is_client()

## Returns true if the MultiplayerRoot is being ran as a server.
func is_server() -> bool:
	return api.is_server()

## Finds the MultiplayerRoot associated with a given Node.
static func fetch(node: Node) -> MultiplayerRoot:
	var tree := node.get_tree()
	if not tree:
		return null
	while node is not MultiplayerRoot and node != tree.root:
		node = node.get_parent()
	if node is MultiplayerRoot:
		return node
	return null

## Returns the total channel count allocated for the MultiplayerRoot.
func get_total_channel_count() -> int:
	return 1 + configuration.channel_count + service_channel_count

#endregion
