extends RefCounted

const FLASK_SIZE := Vector2(235, 281)
const FLASK_INTERIOR := Rect2(10, 88, 215, 182)
const STAND_SIZE := Vector2(1225, 1155)
const STAND_GAUZE_Y := 109.0
const STAND_CENTER_X := 622.0
const RACK_SIZE := Vector2(2172, 724)
const UPPER_SHELF_REGION := Rect2(0, 110, 2172, 230)
const LOWER_SHELF_REGION := Rect2(0, 440, 2172, 240)
const UPPER_SURFACE_Y := 193.0
const LOWER_SURFACE_Y := 529.0
const LIQUID_BOTTLE_SIZE := Vector2(115, 252)
const POWDER_JAR_SIZE := Vector2(230, 197)
const MORTAR_SIZE := Vector2(306, 210)
const MORTAR_FRONT_REGION := Rect2(0, 116, 306, 94)
const PESTLE_SIZE := Vector2(89, 252)
const ROD_SIZE := Vector2(25, 252)
const LAMP_SIZE := Vector2(205, 209)
const WASTE_SIZE := Vector2(212, 252)

static func geometry(area: Rect2) -> Dictionary:
	if not area.position.is_finite() or not area.size.is_finite() or area.size.x <= 0 or area.size.y <= 0:
		return {}
	var w := area.size.x
	var h := area.size.y
	var unit := minf(w / 954.0, h / 438.0)
	var center_x := w * 0.375
	var stand_size := STAND_SIZE * (176.0 * unit / STAND_SIZE.y)
	var stand := Rect2(Vector2(center_x - stand_size.x * STAND_CENTER_X / STAND_SIZE.x, h * 0.59), stand_size)
	var gauze_y := stand.position.y + STAND_GAUZE_Y * stand.size.y / STAND_SIZE.y
	var flask_size := FLASK_SIZE * (232.0 * unit / FLASK_SIZE.y)
	var flask := Rect2(Vector2(center_x - flask_size.x * 0.5, gauze_y - flask_size.y), flask_size)
	var liquid := Rect2(flask.position + FLASK_INTERIOR.position * (flask.size / FLASK_SIZE), FLASK_INTERIOR.size * (flask.size / FLASK_SIZE))
	var mortar_size := MORTAR_SIZE * (100.0 * unit / MORTAR_SIZE.y)
	var mortar := Rect2(Vector2(w * 0.145, h - mortar_size.y - 10.0 * unit), mortar_size)
	# Scale the pestle uniformly to twice the fitted height.
	var previous_pestle_height := minf(w * 0.11 * 279.0 / 266.0, h * 0.35)
	var pestle_size := PESTLE_SIZE * (2.0 * previous_pestle_height / PESTLE_SIZE.y)
	var pestle := Rect2(Vector2(mortar.get_center().x - pestle_size.x * 0.5, mortar.end.y - mortar.size.y * 0.25 - pestle_size.y), pestle_size)
	var rod_height := flask.size.y + 20.0 * unit
	var rod_size := ROD_SIZE * (rod_height / ROD_SIZE.y)
	var rod := Rect2(Vector2(center_x + flask.size.x * 0.05 - rod_size.x * 0.5, flask.position.y - 28.0 * unit), rod_size)
	var lamp_size := LAMP_SIZE * (108.0 * unit / LAMP_SIZE.y)
	var lamp := Rect2(Vector2(center_x - lamp_size.x * 0.5, stand.end.y - lamp_size.y - 11.0 * unit), lamp_size)
	var waste_size := WASTE_SIZE * (110.0 * unit / WASTE_SIZE.y)
	var waste := Rect2(Vector2(w * 0.50, h - waste_size.y - 10.0 * unit), waste_size)
	var rack := Rect2(Vector2(w * 0.62, 0), Vector2(w * 0.38, h))
	var rack_scale := rack.size.x / RACK_SIZE.x
	var upper_baseline := h * 164.0 / 438.0
	var lower_baseline := h * 334.0 / 438.0
	var upper_shelf := Rect2(Vector2(rack.position.x, upper_baseline - (UPPER_SURFACE_Y - UPPER_SHELF_REGION.position.y) * rack_scale), UPPER_SHELF_REGION.size * rack_scale)
	var lower_shelf := Rect2(Vector2(rack.position.x, lower_baseline - (LOWER_SURFACE_Y - LOWER_SHELF_REGION.position.y) * rack_scale), LOWER_SHELF_REGION.size * rack_scale)
	var solvent_bottles: Array[Rect2] = []
	var powder_bottles: Array[Rect2] = []
	var solvent_size := LIQUID_BOTTLE_SIZE * (132.0 * unit / LIQUID_BOTTLE_SIZE.y)
	var powder_size := POWDER_JAR_SIZE * (100.0 * unit / POWDER_JAR_SIZE.y)
	for index in 4:
		var x := rack.position.x + rack.size.x * (float(index) + 0.5) / 4.0
		solvent_bottles.append(Rect2(area.position + Vector2(x - solvent_size.x * 0.5, upper_baseline - solvent_size.y), solvent_size))
	for index in 3:
		var x := rack.position.x + rack.size.x * (float(index) + 0.5) / 3.0
		powder_bottles.append(Rect2(area.position + Vector2(x - powder_size.x * 0.5, lower_baseline - powder_size.y), powder_size))
	var rects := {
		"chart":Rect2(0, 4.0 * unit, w * 0.13, h - 8.0 * unit),
		"flask":flask, "stand":stand, "liquid":liquid, "mortar":mortar, "pestle":pestle,
		"rod":rod, "lamp":lamp, "waste":waste, "rack":rack,
		"upper_shelf":upper_shelf, "lower_shelf":lower_shelf,
		"mortar_powder":Rect2(mortar.position + mortar.size * Vector2(0.24, 0.22), mortar.size * Vector2(0.52, 0.23)),
		"mortar_raw":Rect2(mortar.position + mortar.size * Vector2(0.36, 0.18), mortar.size * Vector2(0.28, 0.35)),
		"mortar_front":Rect2(mortar.position + MORTAR_FRONT_REGION.position * (mortar.size / MORTAR_SIZE), MORTAR_FRONT_REGION.size * (mortar.size / MORTAR_SIZE))
	}
	for id in rects:
		var rect: Rect2 = rects[id]
		rect.position += area.position
		rects[id] = rect
	var result := rects.duplicate()
	result.merge({
		"rects":rects, "solvent_bottles":solvent_bottles, "powder_bottles":powder_bottles,
		"upper_shelf_region":UPPER_SHELF_REGION, "lower_shelf_region":LOWER_SHELF_REGION,
		"mortar_front_region":MORTAR_FRONT_REGION, "unit":unit,
		"gauze_y":area.position.y + gauze_y, "apparatus_center_x":area.position.x + center_x,
		"upper_baseline":area.position.y + upper_baseline, "lower_baseline":area.position.y + lower_baseline,
		"pestle_height_multiplier":2.0, "area":area
	})
	return result
