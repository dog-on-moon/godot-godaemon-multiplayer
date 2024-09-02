@tool
extends MultiplayerNode
class_name ServerNode
## The server node for a multiplayer session.
## Establishes a connection with a ClientNode.

#region Exports

## The port that the server is listening on.
## If the ServerNode exists in a process that has been created through a
## ClientNode's internal scene, this will instead use the ClientNode's port.
@export var port := 27027:
	get:
		if Engine.is_editor_hint():
			return port
		var internal_server_port := SubprocessServer.kwargs.get(ClientNode.KW_INTERNAL_SERVER_PORT, 0)
		return port if internal_server_port == 0 else internal_server_port

## How long the ServerNode should attempt to create a connection before timing out.
@export_range(0.0, 15.0, 0.1, "or_greater") var timeout := 5.0

@export_group("Server Configuration")
#region

## An array of Scripts that are instantiated to the ServerNode
## once a connection has been established.
@export var service_scripts: Array[GDScript] = []

## An array of PackedScenes that are instantiated to the ServerNode
## once a connection has been established.
@export var service_scenes: Array[PackedScene] = []

@export_subgroup("ENet")
#region
## The maximum number of clients that can connect to the server.
@export_range(0, 4095, 1) var max_clients := 32

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
## The key used for setting up a DTLS connection.
@export var dtls_key: CryptoKey = null

## The certificate used for the DTLS server.
## [b]Note:[/b] The certificate should include the full certificate chain
## up to the signing CA (certificates file can be concatenated using a general purpose text editor).
@export var dtls_certificate: X509Certificate = null
#endregion

#endregion

@export_group("Rendering")
#region

## Disables rendering of zones (by turning the ZoneService's visibility off).
@export var disable_rendering := true:
	set(x):
		disable_rendering = x
		if zone_service:
			zone_service.visible = not x

## Determines the type of input events that are propagated to the zones.
## It's best to leave this on, unless you're implementing debug tools.
@export var propagated_inputs := ZoneService.PropagatedInputs.NONE:
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
	if connection_state in [ConnectionState.WAITING, ConnectionState.CONNECTED]:
		push_warning("ServerNode.start_connection was still connecting")
		return false
	connection_state = ConnectionState.DISCONNECTED
	
	# Setup MultiplayerAPI and peer.
	var api := EasyMultiplayerAPI.new()
	api.scene_multiplayer.allow_object_decoding = allow_object_decoding
	api.scene_multiplayer.auth_timeout = authentication_timeout
	get_tree().set_multiplayer(api, get_path())
	var peer = ENetMultiplayerPeer.new()
	
	# Setup DTLS.
	## NOTE: this is unused for now
	## https://github.com/godotengine/godot-proposals/issues/10627
	@warning_ignore("unused_variable")
	var server_options: TLSOptions = null
	if use_dtls_encryption:
		server_options = TLSOptions.server(dtls_key, dtls_certificate)
	
	# Create server connection.
	var error := peer.create_server(port, max_clients, channel_count, in_bandwidth, out_bandwidth)
	if error != OK:
		push_warning("ServerNode.end_connection had error: %s" % error_string(error))
		connection_failed.emit(connection_state)
		return false
	
	var start_t := Time.get_ticks_msec()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		await get_tree().process_frame
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			push_warning("MultiplayerManager.setup_server could not create ENetMultiplayer peer")
			connection_failed.emit(connection_state)
			return false
		elif (Time.get_ticks_msec() - start_t) > timeout:
			push_warning("Multiplayer.setup_server timed out")
			connection_state = ConnectionState.TIMEOUT
			connection_failed.emit(connection_state)
			return false
	
	api.scene_multiplayer.auth_callback = receive_auth_func
	if not api.scene_multiplayer.peer_authenticating.is_connected(start_auth_func):
		api.scene_multiplayer.peer_authenticating.connect(start_auth_func)
	if not api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.connect(peer_connected.emit)
	if not api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.connect(peer_disconnected.emit)
	
	multiplayer.multiplayer_peer = peer
	connection_success.emit()
	return true

## Closes the server.
func end_connection() -> bool:
	if connection_state != ConnectionState.CONNECTED:
		push_warning("ServerNode.end_connection was not connected")
		return false
	connection_state = ConnectionState.DISCONNECTED
	multiplayer.multiplayer_peer.close()
	var api: EasyMultiplayerAPI = multiplayer
	api.scene_multiplayer.auth_callback = Callable()
	if api.scene_multiplayer.peer_authenticating.is_connected(start_auth_func):
		api.scene_multiplayer.peer_authenticating.disconnect(start_auth_func)
	if api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.disconnect(peer_connected.emit)
	if api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.disconnect(peer_disconnected.emit)
	server_disconnected.emit()
	return true

#endregion

#region Authentication

## The default function for when client/server authentication begins.
## Can be set to implement a more refined authentication procedure.
var start_auth_func := func (id: int):
	send_auth(id, PackedByteArray([1]))

## The default authentication callback from the client after they use send_auth for us.
## Can be set to implement a more refined authentication procedure.
var receive_auth_func := func (id: int, data: PackedByteArray):
	if data == PackedByteArray([id]):
		complete_auth(id)

## Sends authentication information to the server.
func send_auth(id: int, data: PackedByteArray):
	var api: EasyMultiplayerAPI = multiplayer
	api.scene_multiplayer.send_auth(id, data)

## Completes authentication on the server end.
## The client will have to complete authentication as well.
func complete_auth(id: int):
	var api: EasyMultiplayerAPI = multiplayer
	api.scene_multiplayer.complete_auth(id)

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

func is_server() -> bool:
	return true

#endregion

func _validate_property(property: Dictionary) -> void:
	if not use_dtls_encryption:
		if property.name in [
			'dtls_key',
			'dtls_certificate',
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
		if not dtls_key:
			warnings.append("dtls_key must be specified for DTLS encryption.")
		if not dtls_certificate:
			warnings.append("dtls_certificate must be specified for DTLS encryption.")
	return warnings
