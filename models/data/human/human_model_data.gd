@tool
class_name HumanModelData
extends ModelData

@export_enum("male") var body_type: String = "male"

func _init():
	pass

func get_model_type() -> String:
	return "human"
