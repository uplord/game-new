@tool
class_name BabySlimeModelData
extends ModelData

@export_enum("Green") var body_type: String = "Green"

func _init():
	pass

func get_model_type() -> String:
	return "BabySlime"
