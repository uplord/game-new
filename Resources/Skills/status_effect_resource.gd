extends Resource
class_name StatusEffectResource

@export var effect_id: String
@export var effect_name: String

@export_enum("buff", "debuff", "dot", "hot", "stun", "taunt")
var effect_type: String = "buff"

@export_enum(
	"damage",
	"defence",
	"haste",
	"hit_chance",
	"dodge",
	"crit_chance",
	"crit_damage",
	"hp_regen",
	"mp_regen",
)
var stat: String = "damage"

@export var flat_amount: int = 0
@export var percent_amount: float = 0.0

@export var duration: float = 5.0
@export var tick_rate: float = 1.0

@export var max_stacks: int = 1
@export var is_refreshable: bool = true
@export var hide_effect: bool = false
