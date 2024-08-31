extends Node2D

@onready var label: Label = $Label

func _ready() -> void:
	print("Hi, I'm Server!")
	var port := 25565 if MultiplayerManager.internal_server_port == -1 else MultiplayerManager.internal_server_port
	label.text = label.text % port
	while not await MultiplayerManager.setup_server(port):
		print('Awaiting open port...')
		await get_tree().create_timer(1.0).timeout
	label.text += '\nSetup!'
	print('Server setup.')
