class_name ModelData
extends Resource

enum FacingDirection {
	RIGHT,
	LEFT
}

@export var default_scale := 1.0
@export var facing_direction: FacingDirection = FacingDirection.RIGHT

func get_model_type() -> String:
	return ""
