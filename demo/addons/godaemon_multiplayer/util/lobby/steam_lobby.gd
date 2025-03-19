extends Node
class_name SteamLobby
## A node representing the existence of a connected Steam lobby.
## (TODO: This is currently very barebones,
## 		since I'm not using most of the lobby API,
## 		but it can be extended to implement most of Steam's lobby callbacks.)

## Integer representing the current lobby ID.
var lobby_id := 0

## The steam ID of the lobby owner.
var lobby_owner: int

func _ready() -> void:
	lobby_owner = Steam.getLobbyOwner(lobby_id)

func _exit_tree() -> void:
	Steam.leaveLobby(lobby_id)

func leave_lobby():
	Steam.leaveLobby(lobby_id)
	queue_free()

func set_lobby_data(key: String, value: String) -> bool:
	if not Steam.setLobbyData(lobby_id, key, value):
		push_warning("Could not set lobby data: [%s, %s, %s]" % [lobby_id, key, value])
		return false
	return true
