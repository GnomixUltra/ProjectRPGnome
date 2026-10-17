extends SceneTree


func _init() -> void:
	var found := []
	for c in ClassDB.get_class_list():
		var lc := c.to_lower()
		if "triangle" in lc or "trimesh" in lc:
			found.append(c)
	print("TRI_CLASSES: ", found)
	print("GodotPhysicsServer3D: ", ClassDB.class_exists("GodotPhysicsServer3D"))
	print("JoltPhysicsServer3D: ", ClassDB.class_exists("JoltPhysicsServer3D"))
	quit()
