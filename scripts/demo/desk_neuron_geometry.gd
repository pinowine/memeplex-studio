extends RefCounted

static var _templates: Dictionary = {}
static var _arbors: Dictionary = {}

static func template(identity: String, kernel_id: String) -> Dictionary:
	var key := identity+"|"+kernel_id
	if _templates.has(key): return _templates[key]
	var rng := RandomNumberGenerator.new()
	rng.seed=key.hash()
	var paths: Array[Dictionary]=[]
	var count := 7 + posmod(kernel_id.hash(),3)
	var offset := rng.randf_range(-.35,.35)
	for index in count:
		var angle := TAU*float(index)/count+offset+rng.randf_range(-.15,.15)
		var direction := Vector2.from_angle(angle)
		var length := rng.randf_range(28,45)
		var curve := _curve(Vector2.ZERO,direction*length,rng.randf_range(-6,6),9)
		paths.append({"points":curve,"width":rng.randf_range(1.7,2.8),"depth":0,"delay":.03})
		if index%2==0: _branch(curve[5],direction.rotated(rng.randf_range(-.3,.3)),length*.48,2,rng,paths,.03+.97*5.0/8.0)
	var soma := PackedVector2Array()
	for index in 48:
		var angle := TAU*float(index)/48
		var radius := 8.1+1.3*sin(angle*count+offset)+.55*sin(angle*3+.8)
		soma.append(Vector2.from_angle(angle)*radius)
	var result := {"paths":paths,"soma":soma,"nucleus":Vector2.ZERO,"seed":rng.seed,"kernel_id":kernel_id}
	_templates[key]=result
	return result

static func _curve(start: Vector2,end: Vector2,bend: float,samples: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var normal := (end-start).normalized().orthogonal()
	for index in samples:
		var t := float(index)/(samples-1)
		result.append(start.lerp(end,t)+normal*(sin(t*PI)*bend+sin(t*TAU)*bend*.12))
	return result

static func _branch(start: Vector2,direction: Vector2,length: float,depth: int,rng: RandomNumberGenerator,paths: Array[Dictionary],delay: float) -> void:
	if depth<=0: return
	for side in [-1,1]:
		var next := direction.rotated(side*rng.randf_range(.30,.62))
		var curve := _curve(start,start+next*length,rng.randf_range(-2,2),6)
		paths.append({"points":curve,"width":float(depth)*.38+.20,"depth":4-depth,"delay":delay})
		_branch(curve[4],next,length*.58,depth-1,rng,paths,delay+(1.0-delay)*.8)

static func transform_path(path: PackedVector2Array,center: Vector2,scale_value: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in path: result.append(center+point*scale_value)
	return result

static func disc(center: Vector2,radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in 20: result.append(center+Vector2.from_angle(TAU*float(index)/20)*radius)
	return result

static func grown(path: PackedVector2Array,growth: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if path.size()<2 or growth<=0.0:return result
	var progress := clampf(growth,0,1)*(path.size()-1)
	var whole := floori(progress)
	for index in whole+1:result.append(path[index])
	if whole<path.size()-1:
		var tip := path[whole].lerp(path[whole+1],progress-whole)
		if result[-1].distance_squared_to(tip)>.000001:result.append(tip)
	return result

static func stroke(path: PackedVector2Array,growth: float,width: float,tip_width: float=.10) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	var points := grown(path,growth)
	for index in maxi(0,points.size()-1):
		var start: Vector2=points[index]
		var end: Vector2=points[index+1]
		if start.distance_squared_to(end)<.000001:continue
		var normal := (end-start).normalized().orthogonal()
		var first := lerpf(width,tip_width,float(index)/(path.size()-1))
		var last := lerpf(width,tip_width,minf(growth,float(index+1)/(path.size()-1)))
		# Convex segment fills avoid partial-growth self-intersections.
		result.append(PackedVector2Array([start+normal*first,end+normal*last,end-normal*last,start-normal*first]))
		result.append(disc(start,first))
		result.append(disc(end,last))
	return result

static func cell(center: Vector2,radius: float,identity: String,kernel_id: String,growth: float=1.0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	if growth<=0.0:return result
	var data := template(identity,kernel_id)
	var scale_value := radius/8.0
	var soma_scale := scale_value*minf(1.0,growth*4.0)
	if soma_scale*8.0>.02:result.append(transform_path(data.soma,center,soma_scale))
	for record: Dictionary in data.paths:
		var progress := clampf((growth-float(record.delay))/(1.0-float(record.delay)),0.0,1.0)
		result.append_array(stroke(transform_path(record.points,center,scale_value),progress,float(record.width)*scale_value,.10*scale_value))
	return result

static func triangulate(polygon: PackedVector2Array) -> PackedInt32Array:
	if polygon.size()<3:return PackedInt32Array()
	var local := PackedVector2Array()
	var origin: Vector2=polygon[0]
	for point in polygon:local.append(point-origin)
	return Geometry2D.triangulate_polygon(local)

static func mask_mesh(polygons: Array[PackedVector2Array]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for polygon in polygons:
		var triangles := triangulate(polygon)
		if triangles.is_empty():
			push_error("Invalid neuron polygon after local triangulation")
			continue
		var offset := vertices.size()
		for point in polygon:vertices.append(Vector3(point.x,point.y,0))
		for index in triangles:indices.append(offset+index)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_INDEX]=indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func arbor(path: PackedVector2Array,growth: float,width: float,identity: String) -> Array[PackedVector2Array]:
	var key := identity+str(path)
	if not _arbors.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed=identity.hash()
		var records: Array[Dictionary]=[]
		for fraction in [.22,.43,.65,.83]:
			var at := clampi(roundi(float(fraction)*(path.size()-1)),1,path.size()-2)
			var direction := (path[at+1]-path[at-1]).normalized()
			for side in [-1,1]:
				var length := minf(48.0,path[0].distance_to(path[-1])*.20)*rng.randf_range(.7,1.0)
				_branch(path[at],direction.rotated(side*.85),length,2,rng,records,float(fraction))
		_arbors[key]=records
	var result := stroke(path,growth,width,.12)
	for record: Dictionary in _arbors[key]:
		var progress := clampf((growth-float(record.delay))/maxf(.1,1.0-float(record.delay)),0.0,1.0)
		result.append_array(stroke(record.points,progress,float(record.width),.10))
	return result
