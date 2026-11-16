extends Node2D

class CountryInk extends Node2D:
	var terrain: Node2D
	var country: int
	func _draw() -> void:
		for mesh: ArrayMesh in terrain.meshes[country]:
			draw_mesh(mesh, null, Transform2D.IDENTITY, terrain._country_color(country))

var _countries: Array[CountryInk] = []

func rebuild() -> void:
	for country in _countries:
		remove_child(country)
		country.queue_free()
	_countries.clear()
	var terrain := get_parent()
	for i in terrain.meshes.size():
		var country := CountryInk.new()
		country.terrain = terrain
		country.country = i
		country.show_behind_parent = true
		country.use_parent_material = true
		add_child(country)
		_countries.append(country)
	queue_redraw()

func refresh_countries(indices: Array[int]) -> void:
	for country in _countries:
		if country.country in indices: country.queue_redraw()
	if not indices.is_empty(): queue_redraw()

func _draw() -> void:
	var terrain := get_parent()
	if terrain.meshes.is_empty():
		return
	# Enclave fills cover the host; ownership holes are stored in the geometry.
	for enclave: Dictionary in terrain.world.enclaves:
		draw_mesh(terrain.meshes[enclave.owner][enclave.outline], null, Transform2D.IDENTITY, terrain._country_color(enclave.owner))
