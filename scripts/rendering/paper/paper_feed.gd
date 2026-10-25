## 让纸张网格沿实际出纸口弯曲；坐标换算使用每米 1000 个逻辑像素。
extends RefCounted

var errors: Array[String] = []
var _target: MeshInstance3D
var _curve := 0
var _template_size := Vector2.ZERO
var _bounds := AABB()
var _base_arrays: Array[Array] = []
var _materials: Array[Material] = []
var _normalized_positions: Array[PackedVector3Array] = []
var _residuals: Array[PackedFloat32Array] = []
var _old_derivatives: Array[PackedFloat32Array] = []
var _row_indices: Array[PackedInt32Array] = []
var _row_z := PackedFloat32Array()
var _old_floor := 0.0
var _old_amplitude := 0.0
var _falloff := 0.0
var _thickness := 0.0
var _signature: Array = []
var _report: Dictionary = {}
var _updates := 0

## 测量出纸锚点；返回值同时包含世界空间和桌面逻辑坐标。
static func measure_exit(assembly: Node3D, asset_id: String) -> Dictionary:
	if assembly == null or asset_id not in ["receipt_printer","fax_machine"]: return {}
	var mouth := assembly.find_child(asset_id+"__PaperExit",true,false) as Node3D
	if mouth == null: return {}
	var width := .146 if asset_id == "receipt_printer" else .210
	var right := mouth.global_basis.x.normalized()
	var outward := mouth.global_basis.z.normalized() * (1.0 if asset_id == "receipt_printer" else -1.0)
	var left := mouth.global_position-right*width*.5
	var origin := Vector2(left.x,left.z)*1000.0+Vector2(800,450)
	var lip_name := "receipt_printer__PaperMouth" if asset_id == "receipt_printer" else "fax_machine__RearOutputSlot"
	var lip := assembly.find_child(lip_name,true,false) as MeshInstance3D
	var clearance := 0.0
	if lip != null and lip.mesh != null:
		var box := lip.get_aabb()
		for corner in 8:
			var offset := Vector3(box.size.x if (corner&1)!=0 else 0.0,box.size.y if (corner&2)!=0 else 0.0,box.size.z if (corner&4)!=0 else 0.0)
			clearance = maxf(clearance,(lip.global_transform*(box.position+offset)-mouth.global_position).dot(outward))
	return {"origin":origin,"width":width*1000.0,"angle":Vector2(right.x,right.z).angle(),"height":mouth.global_position.y,"world_origin":mouth.global_position,"outward":outward,"lip_clearance_m":clearance,"lip_node":lip_name,"asset_id":asset_id}

## 保存原始网格，后续变形始终从这份基准计算，避免逐帧累积误差。
func configure(target: MeshInstance3D, curve: int, template_size: Vector2) -> bool:
	if target == null or target.mesh == null or curve not in [1,2] or template_size.x<=0.0 or template_size.y<=0.0:
		_fail("Paper feed requires a real mesh, receipt/fax curve, and positive template dimensions")
		return false
	_target = target
	_curve = curve
	_template_size = template_size
	_bounds = target.get_aabb()
	if _bounds.size.x<=0.0 or _bounds.size.z<=0.0:
		_fail("Paper feed source mesh has empty planar bounds")
		return false
	_base_arrays.clear()
	_materials.clear()
	_signature.clear()
	var far_min := INF
	var far_max := -INF
	var vertices := 0
	for surface in target.mesh.get_surface_count():
		var arrays := target.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if positions.is_empty() or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array or not arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
			_fail("Paper feed source must retain vertices, normals, content UV and Painter UV2")
			return false
		_base_arrays.append(arrays.duplicate(true))
		_materials.append(target.mesh.surface_get_material(surface))
		for point in positions:
			if _native_distance(point.z)>=_bounds.size.z*.85:
				far_min = minf(far_min,point.y)
				far_max = maxf(far_max,point.y)
		vertices += positions.size()
	_thickness = far_max-far_min
	if not is_finite(_thickness) or _thickness<=0.0:
		_fail("Paper feed cannot measure native sheet thickness")
		return false
	_old_floor = _bounds.position.y+_thickness*.5
	var amplitude := _bounds.size.y-_thickness*.5
	var n := 0.0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for arrays in _base_arrays:
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for point in positions:
			var elevation := point.y-_old_floor
			if elevation<amplitude*.05 or elevation>amplitude*.85: continue
			var distance := _native_distance(point.z)
			var value := log(elevation)
			n += 1.0
			sx += distance
			sy += value
			sxx += distance*distance
			sxy += distance*value
	var denominator := n*sxx-sx*sx
	if n<2.0 or absf(denominator)<1e-12:
		_fail("Paper feed cannot measure native bend profile")
		return false
	var slope := (n*sxy-sx*sy)/denominator
	if slope>=0.0:
		_fail("Paper feed bend does not fall away from its output edge")
		return false
	_falloff = -1.0/slope
	_old_amplitude = exp((sy-slope*sx)/n)
	_normalized_positions.clear()
	_residuals.clear()
	_old_derivatives.clear()
	_row_indices.clear()
	_row_z.clear()
	var rows: Dictionary = {}
	var ax := template_size.x/_bounds.size.x
	var az := template_size.y/_bounds.size.z
	for arrays in _base_arrays:
		var original: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var positions := PackedVector3Array()
		var residuals := PackedFloat32Array()
		var derivatives := PackedFloat32Array()
		var indices := PackedInt32Array()
		for point in original:
			var normalized := Vector3((point.x-_bounds.position.x)*ax-template_size.x*.5,0.0,(point.z-_bounds.position.z)*az-template_size.y*.5)
			positions.append(normalized)
			var old_curve := _old_amplitude*exp(-_native_distance(point.z)/_falloff)
			residuals.append(clampf(point.y-_old_floor-old_curve,-_thickness,_thickness))
			derivatives.append(-old_curve/_falloff*(1.0 if curve==1 else -1.0))
			var key := roundi(point.z*10000000.0)
			if not rows.has(key):
				rows[key] = _row_z.size()
				_row_z.append(normalized.z)
			indices.append(int(rows[key]))
		_normalized_positions.append(positions)
		_residuals.append(residuals)
		_old_derivatives.append(derivatives)
		_row_indices.append(indices)
	_report = {"curve":curve,"vertices":vertices,"surfaces":_base_arrays.size(),"native_thickness_m":_thickness,"bend_falloff_m":_falloff,"native_amplitude_m":_old_amplitude,"native_floor_m":_old_floor,"updates":0}
	return true

func sync(source: Control, mouth: Dictionary) -> void:
	if not errors.is_empty() or not is_instance_valid(_target) or source == null: return
	if source.size.x<=.001 or source.size.y<=.001:
		_report.merge({"empty_feed":true,"source_size":source.size},true)
		return
	if not mouth.has("world_origin") or not mouth.has("outward"):
		_fail("Paper feed requires a measured output anchor and outward direction")
		return
	var world_origin: Vector3 = mouth.world_origin
	var outward: Vector3 = mouth.outward
	var clearance := maxf(0.0,float(mouth.get("lip_clearance_m",0.0)))+_thickness
	var transform := _target.global_transform
	var signature: Array = [transform,source.size,world_origin,outward,clearance]
	if signature==_signature: return
	if transform.basis.y.normalized().dot(Vector3.UP)<.999 or transform.basis.y.y<=0.0:
		_fail("Paper feed expects the desktop's upright sheet frame")
		return
	if absf(outward.dot(transform.basis.x))>.00001:
		_fail("Paper feed width must be aligned with the measured output slot")
		return
	_signature = signature
	var started := Time.get_ticks_usec()
	var floor_y := transform.origin.y
	var amplitude := world_origin.y-floor_y
	if amplitude<=0.0:
		_fail("Measured paper exit is not above the sheet's tabletop plane")
		return
	var generated := ArrayMesh.new()
	var overrides: Array[Material] = []
	for surface in _base_arrays.size(): overrides.append(_target.get_surface_override_material(surface))
	var ax := _template_size.x/_bounds.size.x
	var az := _template_size.y/_bounds.size.z
	var inside := 0
	var endpoint_error := 0.0
	var minimum_y := INF
	var maximum_y := -INF
	var row_height := PackedFloat32Array()
	var row_derivative := PackedFloat32Array()
	var row_distance := PackedFloat32Array()
	for z in _row_z:
		var distance := (transform*Vector3(0,0,z)-world_origin).dot(outward)
		var elevation := amplitude*exp(-maxf(0.0,distance-clearance)/_falloff)
		row_height.append(elevation/transform.basis.y.y)
		row_derivative.append((-elevation/_falloff if distance>clearance else 0.0)*outward.dot(transform.basis.z*az)/transform.basis.y.y)
		row_distance.append(distance)
	for surface in _base_arrays.size():
		var arrays: Array = _base_arrays[surface].duplicate()
		var original_normals: PackedVector3Array = _base_arrays[surface][Mesh.ARRAY_NORMAL]
		var positions := _normalized_positions[surface].duplicate()
		var normals := original_normals.duplicate()
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT].duplicate() if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array else PackedFloat32Array()
		for vertex in positions.size():
			var row := _row_indices[surface][vertex]
			var distance := row_distance[row]
			if distance < -.00001: inside += 1
			var point := positions[vertex]
			point.y = row_height[row]+_residuals[surface][vertex]
			positions[vertex] = point
			var world_y := floor_y+point.y*transform.basis.y.y
			minimum_y = minf(minimum_y,world_y)
			maximum_y = maxf(maximum_y,world_y)
			if absf(distance)<.00001: endpoint_error=maxf(endpoint_error,absf(world_y-world_origin.y))
			var dz := row_derivative[row]-_old_derivatives[surface][vertex]
			var normal := original_normals[vertex]
			normals[vertex] = Vector3(normal.x/ax,normal.y,(normal.z-dz*normal.y)/az).normalized()
			if tangents.size()==positions.size()*4:
				var start := vertex*4
				var tangent := Vector3(tangents[start],tangents[start+1],tangents[start+2])
				tangent = Vector3(tangent.x*ax,tangent.y+dz*tangent.z,tangent.z*az).normalized()
				tangents[start]=tangent.x
				tangents[start+1]=tangent.y
				tangents[start+2]=tangent.z
		arrays[Mesh.ARRAY_VERTEX]=positions
		arrays[Mesh.ARRAY_NORMAL]=normals
		if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT]=tangents
		generated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		generated.surface_set_material(surface,_materials[surface])
	_target.mesh = generated
	for surface in overrides.size(): _target.set_surface_override_material(surface,overrides[surface])
	_updates += 1
	_report.merge({"updates":_updates,"empty_feed":false,"mouth_height_m":world_origin.y,"lip_clearance_m":clearance,"floor_height_m":floor_y,"minimum_y_m":minimum_y,"maximum_y_m":maximum_y,"mouth_endpoint_error_m":endpoint_error,"inside_machine_vertices":inside,"source_size":source.size,"rebuild_usec":Time.get_ticks_usec()-started,"preserved_uv":true,"preserved_uv2":true,"preserved_surface_materials":true},true)

func inspection() -> Dictionary:
	var result := _report.duplicate(true)
	result["errors"] = errors.duplicate()
	return result

func _native_distance(z: float) -> float:
	return z-_bounds.position.z if _curve==1 else _bounds.end.z-z

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
