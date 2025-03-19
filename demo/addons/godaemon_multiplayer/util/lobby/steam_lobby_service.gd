extends Node
## An optional singleton to assist in managing Steam lobbies with GodotSteam.

signal lobby_joined(l: SteamLobby)
signal lobby_exited(l: SteamLobby)

## Emitted when we externally request joining a steam lobby.
signal join_requested(lobby_id: int, steam_id: int)

## The externally requested lobby ID.
## Defined if the game is launched externally through a friend's "Join Game".
## Connection to this lobby is not automatic.
var external_requested_lobby_id := 0

func _enter_tree() -> void:
	# Setup signals.
	Steam.join_requested.connect(join_requested.emit)
	
	# Define externally requested lobby id.
	var these_arguments: Array = OS.get_cmdline_args()
	var lobby_idx := these_arguments.find("+connect_lobby")
	if lobby_idx != -1:
		external_requested_lobby_id = int(these_arguments[lobby_idx + 1])
	child_entered_tree.connect(lobby_joined.emit)
	child_exiting_tree.connect(lobby_exited.emit)

## Creates a Steam lobby. Returns the lobby node on success, or null on failure.
func create_lobby(type := Steam.LOBBY_TYPE_PUBLIC, max_members := 4, data: Dictionary[String, String] = {}) -> SteamLobby:
	Steam.createLobby(type, max_members)
	var result: Array = await Steam.lobby_created
	var connected: int = result[0]
	var lobby_id: int = result[1]
	if connected:
		var lobby := SteamLobby.new()
		lobby.lobby_id = lobby_id
		add_child(lobby)
		for key in data:
			if not lobby.set_lobby_data(key, data[key]):
				push_warning("Could not set lobby data: [%s, %s, %s]" % [lobby_id, key, data[key]])
		return lobby
	else:
		return null

## Attempts to join a steam lobby. Returns an array with either one of two contents:
## - [SteamLobby], on success
## - [int], for failure response code
func join_lobby(lobby_id: int) -> Array:
	Steam.joinLobby(lobby_id)
	var result: Array = await Steam.lobby_joined
	var _lobby: int = result[0]
	var _permissions: int = result[1]
	var _locked: bool = result[2]
	var response: int = result[3]
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		var lobby := SteamLobby.new()
		lobby.lobby_id = lobby_id
		add_child(lobby)
		return [lobby]
	return [response]

## Returns an array of lobby IDs.
## You can call Steam.addRequestLobbyList functions prior to narrow the result.
func request_lobby_list() -> Array:
	Steam.requestLobbyList()
	return await Steam.lobby_match_list

## Gets the owner of a lobby ID.
func get_lobby_owner(lobby_id: int) -> int:
	Steam.getLobbyOwner(lobby_id)
	return 0
