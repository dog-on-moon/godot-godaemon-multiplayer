extends ServiceBase
class_name UsernameService
## Assigns usernames to new clients, allows them to change their usernames.

const USERNAME_KEY := &"name"
const MAX_USERNAME_LENGTH := 16

## Emitted when a peer's username updates.
signal username_updated(peer: int, username: StringName)

## Emitted when a local username request failed.
signal username_request_failed()

@onready var peer_service: PeerService = mp.get_service(PeerService)

func _ready() -> void:
	mp.peer_connected.connect(_setup_peer_name)
	peer_service.full_updated.connect(
		func ():
			for peer in peer_service.get_peers():
				username_updated.emit(peer, get_username(peer))
	)
	peer_service.peer_key_updated.connect(
		func (peer: int, key: Variant):
			if key == USERNAME_KEY:
				username_updated.emit(peer, get_username(peer))
	)
	mp.api.set_rpc_ratelimit(self, &"_request_username", 2, 1.0)
	mp.api.set_rpc_server_receive_only(self, &"_request_username")
	mp.api.set_node_channel(self, peer_service.get_initial_channel(mp))

func _setup_peer_name(peer: int):
	if mp.is_server():
		var idx := 1
		while peer_service.find_peers(USERNAME_KEY, &"Player%s" % idx):
			idx += 1
		peer_service.set_data(peer, USERNAME_KEY, &"Player%s" % idx)

func get_username(peer: int) -> StringName:
	match peer:
		0:
			return &"Everyone"
		1:
			return &"Server"
		_:
			return peer_service.get_data(peer, USERNAME_KEY, &"Unnamed")

func get_local_username() -> StringName:
	if mp.is_server():
		return &"Server"
	return peer_service.get_data(mp.local_peer, USERNAME_KEY, &"Unnamed")

## Requests a username on the client.
func request_username(username: StringName):
	assert(mp.is_client())
	_request_username.rpc(username)

@rpc("any_peer")
func _request_username(username: StringName):
	set_username_server(mp.get_remote_sender_id(), username)

## Sets the username on the server,
func set_username_server(peer: int, username: StringName):
	assert(mp.is_server())
	var new_username := StringName(username.substr(0, MAX_USERNAME_LENGTH))
	if peer_service.find_peers(USERNAME_KEY, new_username):
		_username_request_failed.rpc_id(peer)
		return
	peer_service.set_data(peer, USERNAME_KEY, new_username)

@rpc()
func _username_request_failed():
	username_request_failed.emit()
