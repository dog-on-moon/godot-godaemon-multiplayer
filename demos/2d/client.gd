extends Node2D

const SERVER = preload("res://demos/2d/server.tscn")

@onready var label: Label = $Label

@export var address := "127.0.0.1"
@export var port := 25565
@export_category("Internal Server")
@export var create_internal_server := true
@export var headless_internal_server := true


func _ready() -> void:
	if create_internal_server:
		if not MultiplayerManager.create_internal_server(SERVER, port, headless_internal_server):
			get_tree().quit()
		MultiplayerManager.internal_server_closed.connect(get_tree().quit)
	
	label.text = label.text % port
	
	print("Hi, I'm Client!")
	while not await MultiplayerManager.setup_client(address, port):
		print('Reconnecting...')
	print('Client setup.')
	label.text += '\nSetup!'
