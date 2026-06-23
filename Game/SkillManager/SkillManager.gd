extends Node

var skills := {}

const SKILLS_FOLDER := "res://Resources/Skills"

func _ready():
	load_skills()


func load_skills():
	skills.clear()

	var dir := DirAccess.open(SKILLS_FOLDER)
	if dir == null:
		push_warning("Could not open skills folder: %s" % SKILLS_FOLDER)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "tres":
			var skill_path := "%s/%s" % [SKILLS_FOLDER, file_name]
			var skill: SkillResource = load(skill_path)
			if skill != null and skill.skill_id != "":
				skills[skill.skill_id] = skill
		file_name = dir.get_next()
	dir.list_dir_end()


func get_skill(id: String) -> SkillResource:
	return skills.get(id)
