@tool
extends Marker2D

@onready var sprite: Sprite2D = $Direction

enum TargetDirection {
	LEFT = -1,
	RIGHT = 1,
}
enum TeleportDirection { BASE, UP, DOWN, LEFT, RIGHT, UPLEFT, UPRIGHT, DOWNLEFT, DOWNRIGHT }

@export var target_map: String = ""
@export var target_scene: String = ""
@export var target_teleport: String = ""
@export var target_direction: TargetDirection = TargetDirection.RIGHT
@export var trigger_radius: float = 48.0
@export var teleport_direction: TeleportDirection = TeleportDirection.UP


func _ready() -> void:
	sprite.texture = get_texture_from_direction(teleport_direction)


func get_target_facing() -> int:
	return -1 if target_direction == TargetDirection.LEFT else 1


func get_teleport_key() -> String:
	return "%s/%s" % [get_path(), name]


func get_texture_from_direction(dir: TeleportDirection) -> Texture2D:
	if dir == TeleportDirection.BASE:
		return null

	var name_map := {
		TeleportDirection.UP: "Up",
		TeleportDirection.DOWN: "Down",
		TeleportDirection.LEFT: "Left",
		TeleportDirection.RIGHT: "Right",
		TeleportDirection.UPLEFT: "UpLeft",
		TeleportDirection.UPRIGHT: "UpRight",
		TeleportDirection.DOWNLEFT: "DownLeft",
		TeleportDirection.DOWNRIGHT: "DownRight",
	}

	var file_name = name_map.get(dir, "Up")
	var path = "res://entities/teleports/art/%s.png" % file_name

	if ResourceLoader.exists(path):
		return load(path) as Texture2D

	return null
