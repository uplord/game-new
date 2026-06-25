extends Node
class_name PlayerUtil

enum PlayerPose {
	IDLE,
	FIGHT,
	HEAL,
	DEAD,
	RUNNING
}

static func to_anim_name(pose: int) -> String:
	match pose:
		PlayerPose.IDLE: return "Idle"
		PlayerPose.FIGHT: return "Fight"
		PlayerPose.HEAL: return "Heal"
		PlayerPose.DEAD: return "Dead"
		PlayerPose.RUNNING: return "Running"
		_: return "Idle"
