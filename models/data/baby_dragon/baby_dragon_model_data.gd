@tool
class_name BabyDragonModelData
extends ModelData

@export_enum("fire_dragon") var body_type: String = "fire_dragon"

func _init():
	pass

func get_model_type() -> String:
	return "baby_dragon"
