extends Node3D

# 牌桌各区保留到状态变化为止，动画随所属节点一起清理。
var _sections := {}
var _snapshots := {}
var _wall_tiles: Array[Node3D] = []
var _visible_wall := 0
var _box_meshes := {}
var _quad_meshes := {}


func begin_section(section_name: String, snapshot: Array) -> Node3D:
	if _snapshots.has(section_name) and _snapshots[section_name] == snapshot:
		return null
	if _sections.has(section_name):
		var previous: Node3D = _sections[section_name]
		remove_child(previous)
		previous.queue_free()
	var section := Node3D.new()
	section.name = section_name
	add_child(section)
	_sections[section_name] = section
	_snapshots[section_name] = snapshot.duplicate(true)
	return section


func add_wall_tile(tile: Node3D) -> void:
	_wall_tiles.append(tile)
	tile.hide()


func update_wall(remaining: int) -> void:
	for i in range(mini(_visible_wall, remaining), maxi(_visible_wall, remaining)):
		_wall_tiles[i].visible = i < remaining
	_visible_wall = remaining


func box_mesh(size: Vector3) -> BoxMesh:
	if not _box_meshes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_box_meshes[size] = mesh
	return _box_meshes[size]


func quad_mesh(size: Vector2) -> QuadMesh:
	if not _quad_meshes.has(size):
		var mesh := QuadMesh.new()
		mesh.size = size
		_quad_meshes[size] = mesh
	return _quad_meshes[size]
