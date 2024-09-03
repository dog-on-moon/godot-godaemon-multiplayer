extends Control

@onready var rich_text_label: RichTextLabel = $RichTextLabel

func info(msg: String):
	if rich_text_label.text:
		rich_text_label.text += '\n' + msg
	else:
		rich_text_label.text = msg

func warn(msg: String):
	return info('[color=yellow]%s[/color]' % msg)

func error(msg: String):
	return info('[color=red]%s[/color]' % msg)
