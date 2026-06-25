extends Resource
class_name SkillResource

@export var skill_id: String
@export var skill_name: String

@export_enum("melee", "magic", "buff", "debuff", "hybrid")
var skill_type: String = "melee"

@export var damage: int = 0

@export var mp_cost: int = 0
@export var cooldown: float = 0.0

@export var target_closest_enemy: bool = false

@export var effects: Array[StatusEffectResource] = []
