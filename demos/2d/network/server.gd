extends Node2D

const LOBBY = preload("res://demos/2d/scenes/lobby.tscn")

@export var port := 25565

var lobby_name: String

func _ready() -> void:
	print("Hi, I'm Server!")
	port = port if MultiplayerManager.internal_server_port == -1 else MultiplayerManager.internal_server_port
	while not await MultiplayerManager.setup_server(port):
		print('Awaiting open port...')
		await get_tree().create_timer(1.0).timeout
	
	lobby_name = MultiplayerManager.add_scene(LOBBY)
	multiplayer.peer_connected.connect(_peer_connected)
	print('Server setup.')

func _peer_connected(peer: int):
	MultiplayerManager.add_interest(peer, lobby_name)
