extends Node2D

@onready var container = self

func _ready() -> void:
	SceneManager.setup(container)

	if not ServerManager.is_server:	
		ServerManager.start_client(ServerManager.SERVER_IP)
		ServerManager.server_lost.connect(_on_server_lost)
		ServerManager.server_ready.connect(_on_server_ready)


func _on_server_ready():
	#print("READY")
	SceneManager.load_map()
	SceneManager.load_camera()
	
	await get_tree().process_frame
	ServerManager.send_to_server({
		"type": "c_request_sync"
	})


func _on_server_lost():
	pass
	#print("LOST")
