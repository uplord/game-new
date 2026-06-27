extends Node
class_name BattleCalculator

const PLAYER_MAX_HP := 800.0
const PLAYER_MAX_MP := 100.0
const ENEMY_MAX_HP := 120.0
const ENEMY_MAX_MP := 100.0

const PLAYER_HP_REGEN_PERCENT_PER_SECOND := 0.05
const PLAYER_MP_REGEN_PERCENT_PER_SECOND := 0.08
const STAT_DAMAGE := "damage"
const STAT_DEFENCE := "defence"
const STAT_HASTE := "haste"
const STAT_HIT_CHANCE := "hit_chance"
const STAT_DODGE := "dodge"
const STAT_CRIT_CHANCE := "crit_chance"
const STAT_CRIT_DAMAGE := "crit_damage"
const STAT_HP_REGEN := "hp_regen"
const STAT_MP_REGEN := "mp_regen"

const EFFECT_BUFF := "buff"
const EFFECT_DEBUFF := "debuff"
const EFFECT_DOT := "dot"
const EFFECT_HOT := "hot"
const EFFECT_STUN := "stun"
const EFFECT_TAUNT := "taunt"


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property in resource.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


static func resource_get(resource: Resource, property_name: String, default_value = null):
	if resource == null:
		return default_value
	if not resource_has_property(resource, property_name):
		return default_value
	var value = resource.get(property_name)
	return default_value if value == null else value


static func effect_resource_to_dictionary(effect: Resource) -> Dictionary:
	if effect == null:
		return {}

	var effect_id := str(resource_get(effect, "effect_id", ""))
	var duration := float(resource_get(effect, "duration", 0.0))
	var tick_rate := float(resource_get(effect, "tick_rate", 1.0))
	var flat_amount := float(resource_get(effect, "flat_amount", 0.0))
	var percent_amount := float(resource_get(effect, "percent_amount", 0.0))

	return {
		"id": effect_id,
		"name": str(resource_get(effect, "effect_name", effect_id)),
		"type": str(resource_get(effect, "effect_type", "buff")),
		"stat": str(resource_get(effect, "stat", "")),
		"flat_amount": flat_amount,
		"percent_amount": percent_amount,
		"duration": duration,
		"tick_rate": max(0.05, tick_rate),
		"max_stacks": max(1, int(resource_get(effect, "max_stacks", 1))),
		"is_refreshable": bool(resource_get(effect, "is_refreshable", true)),
		"hide_effect": bool(resource_get(effect, "hide_effect", false)),
		"source_id": str(resource_get(effect, "source_id", "")),
		"expires_at": 0.0,
		"next_tick_at": 0.0,
		"stacks": 1,
	}


static func skill_resource_to_dictionary(skill: Resource) -> Dictionary:
	var skill_id := str(resource_get(skill, "skill_id", ""))
	var effects := []

	var raw_effects = resource_get(skill, "effects", [])
	if raw_effects is Array:
		for effect in raw_effects:
			if effect is Resource:
				var effect_dict := effect_resource_to_dictionary(effect)
				if not effect_dict.is_empty():
					effects.append(effect_dict)
			elif effect is Dictionary:
				effects.append(effect.duplicate(true))

	return {
		"id": skill_id,
		"name": str(resource_get(skill, "skill_name", skill_id)),
		"type": str(resource_get(skill, "skill_type", "melee")),
		"damage": float(resource_get(skill, "damage", 0.0)),
		"mp_cost": float(resource_get(skill, "mp_cost", 0.0)),
		"cooldown": float(resource_get(skill, "cooldown", 0.0)),
		"duration": float(resource_get(skill, "duration", 0.0)),
		"target_closest_enemy": bool(resource_get(skill, "target_closest_enemy", false)),
		"effects": effects,
	}


static func create_player_battle_state(map: String = "", scene: String = "", instance: int = -1) -> Dictionary:
	return {
		"hp": PLAYER_MAX_HP,
		"max_hp": PLAYER_MAX_HP,
		"mp": PLAYER_MAX_MP,
		"max_mp": PLAYER_MAX_MP,
		"cooldowns": {},
		"effects": [],
		"target_enemy_id": "",
		"map": map,
		"scene": scene,
		"instance": instance,
	}


static func create_enemy_battle_state(enemy_id: String, enemy_name: String, map: String, scene: String, instance: int, max_hp: float, max_mp: float, skill_order: Array) -> Dictionary:
	return {
		"id": enemy_id,
		"name": enemy_name,
		"map": map,
		"scene": scene,
		"instance": instance,
		"hp": max_hp,
		"max_hp": max_hp,
		"mp": max_mp,
		"max_mp": max_mp,
		"cooldowns": {},
		"effects": [],
		"skill_order": skill_order.duplicate(),
		"skill_index": 0,
		"attackers": [],
		"defeated": false,
		"respawn_at": 0.0,
		"next_action_at": 0.0,
	}


static func cooldown_remaining(cooldowns: Dictionary, skill_id: String) -> float:
	return max(0.0, float(cooldowns.get(skill_id, 0.0)) - now())


static func is_on_cooldown(cooldowns: Dictionary, skill_id: String) -> bool:
	return cooldown_remaining(cooldowns, skill_id) > 0.0


static func compact_cooldowns(cooldowns: Dictionary) -> Dictionary:
	var result := {}
	for skill_id in cooldowns.keys():
		var remaining := cooldown_remaining(cooldowns, str(skill_id))
		if remaining > 0.0:
			result[skill_id] = remaining
	return result


static func compact_effects(effects: Array) -> Array:
	var result := []
	var current_time := now()

	for effect in effects:
		if not effect is Dictionary:
			continue

		var expires_at := float(effect.get("expires_at", 0.0))
		var remaining = max(0.0, expires_at - current_time) if expires_at > 0.0 else 0.0

		result.append({
			"id": str(effect.get("id", "")),
			"name": str(effect.get("name", effect.get("id", ""))),
			"type": str(effect.get("type", "")),
			"stat": str(effect.get("stat", "")),
			"flat_amount": float(effect.get("flat_amount", 0.0)),
			"percent_amount": float(effect.get("percent_amount", 0.0)),
			"stacks": int(effect.get("stacks", 1)),
			"remaining": remaining,
			"hide_effect": bool(effect.get("hide_effect", false)),
		})

	return result


static func apply_effect(target: Dictionary, effect: Dictionary, source_id: String = "") -> Dictionary:
	if effect.is_empty():
		return target

	var effects: Array = target.get("effects", [])
	var incoming := effect.duplicate(true)
	var effect_id := str(incoming.get("id", ""))
	if effect_id == "":
		return target
		
	if effect_id == "cleanse":
		var cleaned_effects := []

		for existing in effects:
			if not existing is Dictionary:
				continue

			var t := str(existing.get("type", ""))

			if t in [EFFECT_DEBUFF, EFFECT_DOT]:
				continue

			cleaned_effects.append(existing)

		target["effects"] = cleaned_effects
		return target

	var current_time := now()
	var duration := float(incoming.get("duration", 0.0))
	var max_stacks = max(1, int(incoming.get("max_stacks", 1)))
	var is_refreshable := bool(incoming.get("is_refreshable", true))

	incoming["source_id"] = source_id
	incoming["expires_at"] = current_time + duration if duration > 0.0 else 0.0
	incoming["next_tick_at"] = current_time + float(incoming.get("tick_rate", 1.0))
	incoming["stacks"] = 1

	for i in range(effects.size()):
		var existing = effects[i]
		if not existing is Dictionary:
			continue

		if str(existing.get("id", "")) != effect_id:
			continue

		var current_stacks := int(existing.get("stacks", 1))
		existing["stacks"] = min(max_stacks, current_stacks + 1)

		if is_refreshable:
			existing["expires_at"] = incoming["expires_at"]
			existing["next_tick_at"] = min(float(existing.get("next_tick_at", incoming["next_tick_at"])), float(incoming["next_tick_at"]))

		effects[i] = existing
		target["effects"] = effects
		return target

	effects.append(incoming)
	target["effects"] = effects
	return target


static func apply_effects(target: Dictionary, effects_to_apply: Array, source_id: String = "") -> Dictionary:
	for effect in effects_to_apply:
		if effect is Dictionary:
			target = apply_effect(target, effect, source_id)
	return target


static func process_effects(target: Dictionary) -> Dictionary:
	var effects: Array = target.get("effects", [])
	var changed_effects := []
	var current_time := now()

	for effect in effects:
		if not effect is Dictionary:
			continue

		var expires_at := float(effect.get("expires_at", 0.0))
		if expires_at > 0.0 and current_time >= expires_at:
			continue

		var effect_type := str(effect.get("type", ""))
		var stacks = max(1, int(effect.get("stacks", 1)))

		if effect_type == EFFECT_DOT or effect_type == EFFECT_HOT:
			var next_tick_at := float(effect.get("next_tick_at", 0.0))
			var tick_rate = max(0.05, float(effect.get("tick_rate", 1.0)))

			if current_time >= next_tick_at:
				var amount = float(effect.get("flat_amount", 0.0)) * stacks

				if effect_type == EFFECT_DOT:
					target["hp"] = max(0.0, float(target.get("hp", 0.0)) - amount)
				else:
					var stat := str(effect.get("stat", STAT_HP_REGEN))

					if stat == STAT_MP_REGEN:
						var max_mp := float(target.get("max_mp", PLAYER_MAX_MP))
						var mp_amount = amount + (max_mp * float(effect.get("percent_amount", 0.0)) * stacks)
						target["mp"] = min(max_mp, float(target.get("mp", 0.0)) + mp_amount)
					else:
						var max_hp := float(target.get("max_hp", PLAYER_MAX_HP))
						var hp_amount = amount + (max_hp * float(effect.get("percent_amount", 0.0)) * stacks)
						target["hp"] = min(max_hp, float(target.get("hp", 0.0)) + hp_amount)

				effect["next_tick_at"] = current_time + tick_rate

		changed_effects.append(effect)

	target["effects"] = changed_effects
	return target


static func has_effect(target: Dictionary, effect_type_or_id: String) -> bool:
	for effect in target.get("effects", []):
		if not effect is Dictionary:
			continue
		if str(effect.get("type", "")) == effect_type_or_id:
			return true
		if str(effect.get("id", "")) == effect_type_or_id:
			return true
	return false


static func get_stat_percent(target: Dictionary, stat: String) -> float:
	var total := 0.0

	for effect in target.get("effects", []):
		if not effect is Dictionary:
			continue

		if str(effect.get("stat", "")) != stat:
			continue

		var stacks = max(1, int(effect.get("stacks", 1)))
		total += float(effect.get("percent_amount", 0.0)) * stacks

	return total


static func get_stat_flat(target: Dictionary, stat: String) -> float:
	var total := 0.0

	for effect in target.get("effects", []):
		if not effect is Dictionary:
			continue

		if str(effect.get("stat", "")) != stat:
			continue

		var stacks = max(1, int(effect.get("stacks", 1)))
		total += float(effect.get("flat_amount", 0.0)) * stacks

	return total


static func calculate_player_damage(attacker: Dictionary, defender: Dictionary, skill: Dictionary) -> float:
	var damage := float(skill.get("damage", 0.0))
	damage += get_stat_flat(attacker, STAT_DAMAGE)
	damage *= max(0.0, 1.0 + get_stat_percent(attacker, STAT_DAMAGE))
	damage *= max(0.0, 1.0 - get_stat_percent(defender, STAT_DEFENCE))
	return max(0.0, damage)


static func calculate_enemy_damage(attacker: Dictionary, defender: Dictionary, skill: Dictionary) -> float:
	var damage := float(skill.get("damage", 0.0))
	damage += get_stat_flat(attacker, STAT_DAMAGE)
	damage *= max(0.0, 1.0 + get_stat_percent(attacker, STAT_DAMAGE))
	damage *= max(0.0, 1.0 - get_stat_percent(defender, STAT_DEFENCE))
	return max(0.0, damage)


static func get_skill_cooldown(caster: Dictionary, skill: Dictionary) -> float:
	var base_cooldown := float(skill.get("cooldown", 0.0))
	var haste := get_stat_percent(caster, STAT_HASTE)
	return max(0.05, base_cooldown * max(0.1, 1.0 - haste))


static func regen_player_out_of_battle(player: Dictionary, delta: float) -> Dictionary:
	var current_hp := float(player.get("hp", PLAYER_MAX_HP))
	var max_hp := float(player.get("max_hp", PLAYER_MAX_HP))
	var current_mp := float(player.get("mp", PLAYER_MAX_MP))
	var max_mp := float(player.get("max_mp", PLAYER_MAX_MP))

	if current_hp > 0.0 and current_hp < max_hp:
		player["hp"] = min(max_hp, current_hp + (max_hp * PLAYER_HP_REGEN_PERCENT_PER_SECOND * delta))

	if current_mp < max_mp:
		player["mp"] = min(max_mp, current_mp + (max_mp * PLAYER_MP_REGEN_PERCENT_PER_SECOND * delta))

	return player
