extends Node2D

func _draw() -> void:
	var terrain := get_parent()
	for country in terrain.meshes.size():
		for mesh: ArrayMesh in terrain.meshes[country]:
			draw_mesh(mesh, null, Transform2D.IDENTITY, terrain._country_color(country))
	if terrain.meshes.is_empty():
		return
	# Enclave fills cover the host; ownership holes are stored in the geometry.
	for enclave: Dictionary in terrain.world.enclaves:
		draw_mesh(terrain.meshes[enclave.owner][enclave.outline], null, Transform2D.IDENTITY, terrain._country_color(enclave.owner))
