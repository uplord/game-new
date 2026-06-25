@tool
class_name BabySlimeModelData
extends ModelData

@export_enum("green") var body_type: String = "green"

func _init():
	pass

func get_model_type() -> String:
	return "baby_slime"
