class_name AtlasWorldData
extends RefCounted

var seed_value: int
var territories: Array[TerritoryGeometry] = []
var edges: Array[Dictionary] = []
var groups: Array[PackedInt32Array] = []
var bounds: Rect2
var enclaves: Array[Dictionary] = []
var terrain: TerrainField

func country_at(point: Vector2) -> int:
	for i in territories.size():
		if territories[i].contains(point):
			return i
	return -1

func fingerprint() -> String:
	var bytes := PackedByteArray()
	for territory in territories:
		for outline in territory.outlines:
			bytes.append_array(outline.to_byte_array())
	bytes.append_array(terrain.heights.to_byte_array())
	return bytes.hex_encode().sha256_text()
