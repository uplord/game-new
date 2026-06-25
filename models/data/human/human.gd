@tool
extends Node2D

var body_type: String = "male"

var parts := {
	"BackHand": "back_hand",
	"BackShoulder": "back_shoulder",
	"BackThigh": "back_thigh",
	"BackShin": "back_shin",
	"BackFoot": "back_foot",
	"Chest": "chest",
	"Head": "head",
	"FrontThigh": "front_thigh",
	"FrontShin_Idle": "front_shin",
	"FrontShin_Run": "back_shin",
	"FrontFoot_Idle": "front_foot",
	"FrontFoot_Run": "back_foot",
	"FrontShoulder": "front_shoulder",
	"FrontHand": "front_hand"
}

func _ready() -> void:
	load_body_textures()

func apply_model_data(data: ModelData) -> void:
	if not data is HumanModelData:
		push_error("Human received wrong model data")
		return

	var human_data := data as HumanModelData
	body_type = human_data.body_type

	if is_inside_tree():
		load_body_textures()

func load_body_textures() -> void:
	for node_name in parts:
		var sprite: Sprite2D = get_node("Body/%s/Skin" % node_name)

		var texture_path := (
			"res://models/data/human/art/%s/%s/armour.png"
			% [body_type, parts[node_name]]
		)

		var tex = load(texture_path)

		if tex:
			sprite.texture = tex
		else:
			push_warning("Texture not found: " + texture_path)
