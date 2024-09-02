@tool
extends MultiplayerNode
class_name ClientNode
## The client node for a multiplayer session.
## Establishes a connection with a ServerNode.

#region Exports

## A fully qualified domain name (e.g. "www.example.com")
## or an IP address in IPv4 or IPv6 format (e.g. "192.168.1.1")
## that the server is hosting on.
@export var address := "127.0.0.1"

## The port that the server is listening on.
@export var port := 27027

## How long the ClientNode should attempt to connect to the server before timing out.
@export_range(0.0, 15.0, 0.1, "or_greater") var timeout := 5.0

@export_group("Client Configuration")
#region

## An array of Scripts that are instantiated to the ClientNode
## once a connection has been established.
@export var service_scripts: Array[GDScript] = []

## An array of PackedScenes that are instantiated to the ClientNode
## once a connection has been established.
@export var service_scenes: Array[PackedScene] = []

@export_subgroup("ENet")
#region
## Can be specified to allocate additional ENet channels for RPCs.
## Note that many channels are reserved in advance for zones.
@export_range(0, 255, 1) var channel_count := 0

## Set to limit the incoming bandwidth in bytes per second.
## The default of 0 means unlimited bandwidth.
##
## Note that ENet will strategically drop packets on specific sides of a connection
## between peers to ensure the peer's bandwidth is not overwhelmed.
## The bandwidth parameters also determine the window size of a connection,
## which limits the amount of reliable packets that may be in transit at any given time.
@export_range(0, 65536, 1, "or_greater") var in_bandwidth := 0

## Set to limit the outgoing bandwidth in bytes per second.
## The default of 0 means unlimited bandwidth.
##
## Note that ENet will strategically drop packets on specific sides of a connection
## between peers to ensure the peer's bandwidth is not overwhelmed.
## The bandwidth parameters also determine the window size of a connection,
## which limits the amount of reliable packets that may be in transit at any given time.
@export_range(0, 65536, 1, "or_greater") var out_bandwidth := 0

## When specified, the client will also listen to the given port.
## This is useful for some NAT traversal techniques.
@export var local_port := 0
#endregion

@export_subgroup("Authentication")
#region
## If set to a value greater than 0.0, the maximum amount of time peers can stay
## in the authenticating state, after which the authentication will automatically fail.
@export_range(0.0, 15.0, 0.1, "or_greater") var authentication_timeout := 3.0
#endregion

@export_subgroup("Security")
#region
## When true, objects will be encoded and decoded during RPCs.
## [b]WARNING:[/b] Deserialized objects can contain code which gets executed.
## Do not use this option if the serialized object comes from untrusted sources
## to avoid potential security threat such as remote code execution.
@export var allow_object_decoding := false

## Determines if DTLS encryption is enabled.
@export var use_dtls_encryption := false:
	set(x):
		use_dtls_encryption = x
		update_configuration_warnings()
		notify_property_list_changed()

# @export_subgroup("DTLS Configuration")
## The hostname which the server certificate is validated against.
@export var dtls_hostname := ""

## A custom trusted_chain of certification authorities
## (the default CA list will be used if null).
@export var dtls_trusted_chain: X509Certificate = null

## If you expect the certificate to have a common name other than the server FQDN,
## you can specify an override here.
@export var dtls_common_name_override := ""

## Determines if we should create an unsafe DTLS client, bypassing certificate verification.
## [b]Using this for anything other than testing is not recommended.[/b]
@export var dtls_unsafe_client := false:
	set(x):
		dtls_unsafe_client = x
		update_configuration_warnings()
	get:
		if OS.has_feature('release') and not Engine.is_editor_hint():
			return false
		return dtls_unsafe_client
#endregion

#endregion

@export_group("Internal Server")
#region

const KW_INTERNAL_SERVER_PORT := "_INTERNAL_SERVER_PORT"

## When true, connection attempts will also setup an additional process
## for running an internal server. This process will contain user arguments
## in its creation which define the existence of an internal server.
@export var use_internal_server := false:
	set(x):
		use_internal_server = x
		update_configuration_warnings()
		notify_property_list_changed()

## A scene that contains a ServerNode.
@export_file("*.tscn") var internal_server_scene := "":
	set(x):
		internal_server_scene = x
		update_configuration_warnings()

## When true, the internal server will run as a background process (headless).
@export var headless_internal_server := true

#endregion

@export_group("Rendering")
#region

## Disables rendering of zones (by turning the ZoneService's visibility off).
@export var disable_rendering := false:
	set(x):
		disable_rendering = x
		if zone_service:
			zone_service.visible = not x

## Determines the type of input events that are propagated to the zones.
## It's best to leave this on, unless you're implementing debug tools.
@export var propagated_inputs := ZoneService.PropagatedInputs.ALL:
	set(x):
		propagated_inputs = x
		if zone_service:
			zone_service.propagated_inputs = x

## The default stretch shrink for the ZoneService (see SubViewportContainer).
@export_range(0, 1, 1, "or_greater") var stretch_shrink := 1:
	set(x):
		stretch_shrink = x
		if zone_service:
			zone_service.stretch_shrink = x

#endregion

#endregion

#region Connection

## Attempts a connection to the server.
func start_connection() -> bool:
	# Ensure we are not currently connecting.
	if connection_state in [ConnectionState.WAITING, ConnectionState.AUTHENTICATING, ConnectionState.CONNECTED]:
		push_warning("ClientNode.attempt_connect was still connecting")
		return false
	connection_state = ConnectionState.DISCONNECTED
	
	# Attempt creating an internal server.
	if not _start_internal_server():
		push_warning("ClientNode.attempt_connect could not make internal server")
		connection_failed.emit(connection_state)
		return false
	
	# Setup EasyMultiplayerAPI and peer.
	var api := EasyMultiplayerAPI.new()
	api.scene_multiplayer.allow_object_decoding = allow_object_decoding
	api.scene_multiplayer.auth_timeout = authentication_timeout
	get_tree().set_multiplayer(api, get_path())
	var peer = ENetMultiplayerPeer.new()
	
	# Setup DTLS.
	## NOTE: this is unused for now
	## https://github.com/godotengine/godot-proposals/issues/10627
	@warning_ignore("unused_variable")
	var client_options: TLSOptions = null
	if use_dtls_encryption:
		assert(dtls_hostname)
		if not dtls_unsafe_client:
			client_options = TLSOptions.client(dtls_trusted_chain, dtls_common_name_override)
		else:
			client_options = TLSOptions.client_unsafe()
	
	# Create client connection.
	var error := peer.create_client(address, port, channel_count, in_bandwidth, out_bandwidth, local_port)
	if error != OK:
		push_warning("ClientNode.attempt_connect had error: %s" % error_string(error))
		_end_internal_server()
		connection_failed.emit(connection_state)
		return false
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		push_warning("ClientNode.attempt_connect could not create ENetMultiplayer peer")
		_end_internal_server()
		connection_failed.emit(connection_state)
		return false
	
	# Async wait for connection.
	connection_state = ConnectionState.WAITING
	_start_connect_await()
	multiplayer.multiplayer_peer = peer
	if connection_state == ConnectionState.WAITING:
		await _connect_await_end
	
	# Based on connect result, return true/false.
	match connection_state:
		ConnectionState.CONNECTED:
			if not multiplayer.server_disconnected.is_connected(end_connection):
				multiplayer.server_disconnected.connect(end_connection)
			if not multiplayer.peer_disconnected.is_connected(_on_client_peer_disconnect):
				multiplayer.peer_disconnected.connect(_on_client_peer_disconnect)
			if not multiplayer.peer_connected.is_connected(peer_connected.emit):
				multiplayer.peer_connected.connect(peer_connected.emit)
			if not multiplayer.peer_disconnected.is_connected(peer_disconnected.emit):
				multiplayer.peer_disconnected.connect(peer_disconnected.emit)
			connection_success.emit()
			return true
		_:
			peer.close()
			connection_failed.emit(connection_state)
			_end_internal_server()
			return false

#region Client Async Connect

signal _connect_await_end
var _client_setup_timer: SceneTreeTimer

func _start_connect_await():
	var api: EasyMultiplayerAPI = multiplayer
	api.connected_to_server.connect(_connect_await_result_connected)
	api.server_disconnected.connect(_connect_await_result_disconnected)
	api.connection_failed.connect(_connect_await_result_failed)
	api.scene_multiplayer.auth_callback = _auth_callback
	api.scene_multiplayer.peer_authenticating.connect(_connect_await_result_authentication)
	api.scene_multiplayer.peer_authentication_failed.connect(_connect_await_result_authentication_failed)
	_client_setup_timer = get_tree().create_timer(timeout)
	_client_setup_timer.timeout.connect(_connect_await_result_timeout)

func _connect_await_result_connected():
	_connect_await_result(ConnectionState.CONNECTED)

func _connect_await_result_disconnected():
	_connect_await_result(ConnectionState.DISCONNECTED)

func _connect_await_result_failed():
	_connect_await_result(ConnectionState.DISCONNECTED)

func _connect_await_result_timeout():
	if connection_state == ConnectionState.AUTHENTICATING:
		# we reached authentication, so we're on auth timeout now
		return
	_connect_await_result(ConnectionState.TIMEOUT)

func _connect_await_result_authentication(id: int):
	if id == 1:
		connection_state = ConnectionState.AUTHENTICATING
	start_auth_func.call()

func _connect_await_result_authentication_failed(id: int):
	if id == 1:
		_connect_await_result(ConnectionState.AUTH_TIMEOUT)

func _connect_await_result(state: ConnectionState):
	var api: EasyMultiplayerAPI = multiplayer
	if api.connected_to_server.is_connected(_connect_await_result_connected):
		api.connected_to_server.disconnect(_connect_await_result_connected)
	if api.server_disconnected.is_connected(_connect_await_result_disconnected):
		api.server_disconnected.disconnect(_connect_await_result_disconnected)
	if api.connection_failed.is_connected(_connect_await_result_failed):
		api.connection_failed.disconnect(_connect_await_result_failed)
	api.scene_multiplayer.auth_callback = Callable()
	if api.scene_multiplayer.peer_authenticating.is_connected(_connect_await_result_authentication):
		api.scene_multiplayer.peer_authenticating.disconnect(_connect_await_result_authentication)
	if api.scene_multiplayer.peer_authentication_failed.is_connected(_connect_await_result_authentication_failed):
		api.scene_multiplayer.peer_authentication_failed.disconnect(_connect_await_result_authentication_failed)
	if _client_setup_timer:
		if _client_setup_timer.timeout.is_connected(_connect_await_result_timeout):
			_client_setup_timer.timeout.disconnect(_connect_await_result_timeout)
		_client_setup_timer = null
	connection_state = state
	_connect_await_end.emit()

#endregion

## Ends an active connection with the ServerNode.
func end_connection() -> bool:
	if connection_state != ConnectionState.CONNECTED:
		push_warning("ClientNode.end_connection was not connected")
		return false
	connection_state = ConnectionState.DISCONNECTED
	var api: EasyMultiplayerAPI = multiplayer
	api.multiplayer_peer.close()
	if api.server_disconnected.is_connected(end_connection):
		api.server_disconnected.disconnect(end_connection)
	if api.peer_disconnected.is_connected(_on_client_peer_disconnect):
		api.peer_disconnected.disconnect(_on_client_peer_disconnect)
	if api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.disconnect(peer_connected.emit)
	if api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.disconnect(peer_disconnected.emit)
	server_disconnected.emit()
	_end_internal_server()
	return true

func _on_client_peer_disconnect(peer: int):
	# Forces a disconnection whenever the server peer disconencts
	if connection_state == ConnectionState.CONNECTED and peer == 1:
		end_connection()

#endregion

#region Authentication

## The default function for when client/server authentication begins.
## Can be set to implement a more refined authentication procedure.
var start_auth_func := func ():
	send_auth(PackedByteArray([multiplayer.get_unique_id()]))

## The default authentication callback from the server after they use send_auth for us.
## Can be set to implement a more refined authentication procedure.
var receive_auth_func := func (data: PackedByteArray):
	if data == PackedByteArray([1]):
		complete_auth()

## Sends authentication information to the server.
func send_auth(data: PackedByteArray):
	if connection_state != ConnectionState.AUTHENTICATING:
		push_warning("ClientNode.send_auth can only be done during authentication (ClientNode.start_auth_func and ClientNode.receive_auth_func)")
		return
	var api: EasyMultiplayerAPI = multiplayer
	api.scene_multiplayer.send_auth(1, data)

## Completes authentication on the client end.
## The server will have to complete authentication as well.
func complete_auth():
	var api: EasyMultiplayerAPI = multiplayer
	api.scene_multiplayer.complete_auth(1)

## The internal auth callback for the EasyMultiplayerAPI.
func _auth_callback(id: int, data: PackedByteArray):
	if id == 1:
		receive_auth_func.call(data)

#endregion

#region Internal Server

## The process ID of the internal server.
var internal_server_pid := -1

# Attempts to create the internal server.
# Note that this returns TRUE even when internal server is disabled
# (since it technically didn't fail!)
func _start_internal_server() -> bool:
	if use_internal_server:
		if KW_INTERNAL_SERVER_PORT in SubprocessServer.kwargs:
			# Realistically speaking, we should probably avoid a fork bomb
			return false
		if not internal_server_scene:
			push_warning("ClientNode._start_internal_server server scene unspecified")
			return false
		internal_server_pid = SubprocessServer.create_subprocess(
			internal_server_scene, {
				KW_INTERNAL_SERVER_PORT: port
			}, headless_internal_server
		)
		if internal_server_pid == -1:
			return false
	return true

func _end_internal_server():
	if internal_server_pid != -1:
		SubprocessServer.kill_subprocess(internal_server_pid)

#endregion

#region Services

## Gets all service scripts.
func get_service_scripts() -> Array[GDScript]:
	return service_scripts

## Gets all service scenes.
func get_service_scenes() -> Array[PackedScene]:
	return service_scenes

#endregion

#region Getters

func is_client() -> bool:
	return true

#endregion

func _validate_property(property: Dictionary) -> void:
	if not use_dtls_encryption:
		if property.name in [
			'dtls_hostname',
			'dtls_trusted_chain',
			'dtls_common_name_override',
			'dtls_unsafe_client',
				]:
			property.usage ^= PROPERTY_USAGE_EDITOR
	if not use_internal_server:
		if property.name in [
			'internal_server_scene',
			'headless_internal_server'
				]:
			property.usage ^= PROPERTY_USAGE_EDITOR
	if property.name in [
		'stretch'
			]:
		property.usage ^= PROPERTY_USAGE_EDITOR

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if use_dtls_encryption:
		warnings.append("DTLS encryption is currently disabled.\nhttps://github.com/godotengine/godot-proposals/issues/10627")
		if dtls_unsafe_client:
			warnings.append("dtls_unsafe_client is currently enabled. This is for testing only. It will be disabled in release builds.")
		if not dtls_hostname:
			warnings.append("dtls_hostname must be specified for DTLS encryption.")
	if use_internal_server:
		if not internal_server_scene:
			warnings.append("An internal server scene must be specified for an internal server.")
	return warnings
