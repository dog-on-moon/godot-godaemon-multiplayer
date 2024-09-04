extends RefCounted
class_name PeerAuthenticator
## The default server/client authentication protocol used in the MultiplayerConfig.
## Can be overridden to implement custom authentication protocol.
##
## This class is configured within [class MultiplayerConfig] and describes the
## authentication process that each process uses to secure a connection.
## Both [method client_start_auth] and [method server_start_auth] are called on their
## respective processes at the start of authentication.
## Calling [method send_auth] on the server sends it to [method client_receive_auth] on the client,
## and vice-versa for the client (where [method server_receive_auth] is received instead).
##
## [b]While this can be used to exchange sensitive information (such as passwords),
## you must enable and properly configure DTLS encryption to do it securely.[/b]

var api: GodaemonMultiplayerAPI
var mp: MultiplayerRoot

#region Client

## The default function for when client authentication begins.
## Can be set to implement a more refined authentication procedure.
func client_start_auth():
	send_auth(PackedByteArray([api.get_unique_id()]))

## The default authentication callback from the server after they use send_auth for us.
## Can be set to implement a more refined authentication procedure.
func client_receive_auth(data: PackedByteArray):
	if data == PackedByteArray([1]):
		complete_auth()

#endregion

#region Server

## The default function for when client/server authentication begins.
## Can be set to implement a more refined authentication procedure.
func server_start_auth(peer: int):
	send_auth(PackedByteArray([1]), peer)

## The default authentication callback from the client after they use send_auth for us.
## Can be set to implement a more refined authentication procedure.
func server_receive_auth(peer: int, data: PackedByteArray):
	if data == PackedByteArray([peer]):
		complete_auth(peer)

#endregion

## Sends authentication information to the target peer.
func send_auth(data: PackedByteArray, peer := 1):
	assert(peer != api.get_unique_id(), "Incorrect target peer")
	api.scene_multiplayer.send_auth(peer, data)

## Completes authentication with the target peer.
## Both the client and server must call this.
func complete_auth(peer := 1):
	assert(peer != api.get_unique_id(), "Incorrect target peer")
	api.scene_multiplayer.complete_auth(peer)
