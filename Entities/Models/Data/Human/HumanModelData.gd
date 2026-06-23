@tool
class_name HumanModelData
extends ModelData

@export_enum("Male") var body_type: String = "Male"

func _init():
	pass

func get_model_type() -> String:
	return "Human"
