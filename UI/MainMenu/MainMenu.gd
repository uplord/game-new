extends CanvasLayer

signal start_pressed

@onready var connect_button: Button = $CenterContainer/Button


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)


func _on_connect_pressed() -> void:
	start_pressed.emit()
