class_name BabyDragonModelData
extends ModelData

@export_enum("FireDragon") var body_type: String = "FireDragon"

func _init():
	default_scale = 1.0

func get_model_type() -> String:
	return "BabyDragon"
