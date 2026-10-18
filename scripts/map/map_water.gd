extends Node2D

func _draw() -> void:
	var terrain := get_parent().get_parent()
	# Opaque fills merge inside the authored CanvasGroup before zoom opacity is applied.
	draw_mesh(terrain.river_mesh, null, Transform2D.IDENTITY, terrain.settings.river_color)
	for mesh in terrain.lake_meshes:
		draw_mesh(mesh, null, Transform2D.IDENTITY, terrain.settings.lake_color)
