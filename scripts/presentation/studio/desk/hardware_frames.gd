extends RefCounted

# The 3D models render the hardware; these dimensions keep its input layout aligned.
static func texture(dimensions: Vector2) -> PlaceholderTexture2D:
	var frame := PlaceholderTexture2D.new()
	frame.size = dimensions
	return frame
