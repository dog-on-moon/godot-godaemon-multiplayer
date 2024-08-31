extends Control

@onready var domain_label: Label = $DomainLabel
@onready var peer_label: Label = $PeerLabel

func _ready() -> void:
	domain_label.text = "Server" if MultiplayerManager.is_server() else "Client"
	
	MultiplayerManager.hook_interest_update(update_peer_text)
	update_peer_text()

func update_peer_text():
	var peer_names := PackedStringArray()
	for peer in MultiplayerManager.get_node_interest(self):
		peer_names.append(str(peer))
	peer_label.text = 'Peers:\n' + '\n'.join(peer_names)
