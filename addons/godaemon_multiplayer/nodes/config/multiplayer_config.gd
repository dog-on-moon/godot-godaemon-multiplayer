@tool
extends Resource
class_name MultiplayerConfig
## Configuration data for MultiplayerRoots.
## This should be shared between connecting ClientRoots and ServerRoots.

const DEFAULT_AUTHENTICATOR = preload("res://addons/godaemon_multiplayer/nodes/config/peer_authenticator.gd")

# @export_group("Services")
#region

## An array of ServiceBase scripts that are instantiated to the ServerRoot
## once a connection has been established.
@export var services: Array[Script] = []

#endregion

@export_group("ENet")
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

@export_group("Authentication")
#region
## How long the ServerRoot/ClientRoot should attempt to create a connection before timing out.
@export_range(0.0, 15.0, 0.1, "or_greater") var connection_timeout := 5.0

## The authentication protocol used by the client/server to establish a connection.
## Can be overridden to implement custom authentication protocol.
@export var authenticator: Script = DEFAULT_AUTHENTICATOR:
	set(x):
		if not x:
			x = DEFAULT_AUTHENTICATOR
		authenticator = x

## If set to a value greater than 0.0, the maximum amount of time peers can stay
## in the authenticating state, after which the authentication will automatically fail.
@export_range(0.0, 15.0, 0.1, "or_greater") var authentication_timeout := 3.0
#endregion

@export_group("Security")
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
		notify_property_list_changed()
#endregion

@export_group("Peer Timeout")
#region
## A base factor that, multiplied by a value based on the average round trip time,
## will determine the timeout limit for a reliable packet.
## When that limit is reached, the timeout will be doubled.
@export_range(0, 1.0, 0.01, "or_greater") var peer_timeout := 0.032

## When the peer_timeout factor has surpassed timeout_min, the peer will be disconnected.
@export_range(0.0, 120.0, 0.1, "or_greater") var peer_timeout_minimum := 45.0

## A fixed timeout for which any packet must be acknowledged, or the peer will be dropped.
@export_range(0.0, 120.0, 0.1, "or_greater") var peer_timeout_maximum := 60.0

## Determines if peer timeout is enabled.
@export var enable_peer_timeout := true

## Determines if peer timeout is enabled in the editor.
@export var enable_dev_peer_timeout := false

#endregion
