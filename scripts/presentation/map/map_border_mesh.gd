extends MeshInstance2D

const TRIANGLES := [5, 6, 10, 5, 10, 9, 5, 4, 8, 5, 8, 9, 6, 7, 11, 6, 11, 10, 5, 1, 2, 5, 2, 6, 9, 13, 14, 9, 14, 10, 5, 1, 0, 5, 0, 4, 6, 2, 3, 6, 3, 7, 9, 13, 12, 9, 12, 8, 10, 14, 15, 10, 15, 11]
const OPAQUE_VERTICES := [5, 6, 9, 10]

func set_lines(points: PackedVector2Array, ink: Color, width: float) -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var line_count := points.size() / 2
	vertices.resize(line_count * 16)
	colors.resize(line_count * 16)
	indices.resize(line_count * 54)
	# Match the line feathering so batching preserves the original border at every zoom.
	var core_width := width * 0.5
	var feather := 1.25 * minf(core_width, 1.0)
	for line in line_count:
		var from := points[line * 2]
		var to := points[line * 2 + 1]
		var direction := (from - to).normalized()
		var normal := direction.orthogonal()
		var half_width := normal * core_width * 0.5
		var side := normal * feather
		var cap := direction * feather
		var a := from + half_width
		var b := from - half_width
		var c := to - half_width
		var d := to + half_width
		var grid := [a + side + cap, a + cap, b + cap, b - side + cap, a + side, a, b, b - side, d + side, d, c, c - side, d + side - cap, d - cap, c - cap, c - side - cap]
		for i in 16:
			vertices[line * 16 + i] = Vector3(grid[i].x, grid[i].y, 0)
			colors[line * 16 + i] = Color(1, 1, 1, 1 if i in OPAQUE_VERTICES else 0)
		for i in TRIANGLES.size(): indices[line * 54 + i] = line * 16 + TRIANGLES[i]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var border_mesh := ArrayMesh.new()
	border_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = border_mesh
	self_modulate = ink
