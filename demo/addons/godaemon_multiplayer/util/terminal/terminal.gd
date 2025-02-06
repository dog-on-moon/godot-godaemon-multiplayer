extends Control

@onready var rich_text_label: RichTextLabel = $RichTextLabel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func info(msg: String):
	if not is_node_ready():
		await ready
	if rich_text_label.text:
		rich_text_label.text += '\n' + msg
	else:
		rich_text_label.text = msg

func warn(msg: String):
	return await info('[color=yellow]%s[/color]' % msg)

func error(msg: String):
	return await info('[color=red]%s[/color]' % msg)
