extends Control

@onready var domain_label: Label = $DomainLabel

func _ready() -> void:
	domain_label.text = "Server" if MultiplayerManager.is_server() else "Client"
