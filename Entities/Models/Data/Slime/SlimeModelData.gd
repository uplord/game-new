class_name SlimeModelData
extends ModelData

@export_enum("Baby", "Adult", "King") var body_type: String = "Baby"

func _init():
	default_scale = 1.0

func get_model_type() -> String:
	return "Slime"
