extends Area2D
class_name Item

signal arrived

@export var follow_speed := 15.0
@export var item_type: String = "Apple"

const POP_DURATION := 0.3
const NORMAL_SCALE := 0.75

var _is_at_target := false
var current_shelf = null
var is_dragging := false
var offset: Vector2 = Vector2.ZERO
var mouse_over := false
var start_position: Vector2
var target_position: Vector2
var _position_initialized := false

func _ready():
	add_to_group("items")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	scale = Vector2(NORMAL_SCALE, NORMAL_SCALE)
	call_deferred("_init_position")
	

func _init_position():
	if not _position_initialized:
		start_position = global_position
		target_position = global_position
		_position_initialized = true

func set_slot_position(slot_pos: Vector2):
	global_position = slot_pos
	target_position = slot_pos
	start_position = slot_pos
	_position_initialized = true
	_is_at_target = false

func confirm_slot_position(slot_pos: Vector2):
	target_position = slot_pos
	start_position = slot_pos
	_is_at_target = false

func set_dimmed(dimmed: bool):
	# Back-layer items stay visible but are darkened and non-interactable
	input_pickable = !dimmed
	scale = Vector2(0.60, 0.60)
	modulate = Color(0.3, 0.3, 0.3, 1.0) if dimmed else Color.WHITE

func restore_color():
	# Tween back to full color so the reveal feels smooth
	var tween = create_tween()
	scale = Vector2(0.75, 0.75)
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)


func _on_mouse_entered():
	mouse_over = true
	if not is_dragging:
		scale = Vector2(0.9, 0.9)

func _on_mouse_exited():
	mouse_over = false
	if not is_dragging:
		scale = Vector2(NORMAL_SCALE, NORMAL_SCALE)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and mouse_over:
			if not _position_initialized:
				return
			is_dragging = true
			_is_at_target = false
			z_index = 10
			offset = get_global_mouse_position() - global_position

		elif not event.pressed and is_dragging:
			is_dragging = false
			z_index = 1
			scale = Vector2(NORMAL_SCALE, NORMAL_SCALE)

			var target_shelf = _get_shelf_at_position(global_position)

			if target_shelf == null:
				# Dropped in void — snap back
				target_position = start_position
				return

			if target_shelf == current_shelf:
				# Same shelf — rearrange only, no removal needed
				target_shelf.add_item(self)
				return

			# --- Cross-shelf transfer ---
			# Remove from source FIRST so the slot is free on source,
			# and the item isn't double-counted during add_item on target.
			var old_shelf = current_shelf
			if old_shelf != null:
				old_shelf.remove_item(self)

			var success = target_shelf.add_item(self)

			if success:
				current_shelf = target_shelf
			else:
				# Target rejected — put it back on the source shelf
				if old_shelf != null:
					old_shelf.add_item(self)
					current_shelf = old_shelf
				else:
					target_position = start_position

func _get_shelf_at_position(pos: Vector2):
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var results = space.intersect_point(query)
	for result in results:
		var obj = result.collider
		if obj.is_in_group("shelves"):
			return obj
	return null

func _process(delta):
	if not _position_initialized:
		return
	if is_dragging:
		_is_at_target = false
		global_position = global_position.lerp(
			get_global_mouse_position() - offset, follow_speed * delta)
	else:
		global_position = global_position.lerp(target_position, follow_speed * delta)
		if not _is_at_target and global_position.distance_to(target_position) < 0.5:
			global_position = target_position
			_is_at_target = true
			arrived.emit()

func pop_effect():
	set_process_input(false)
	set_process(false)
	if mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.disconnect(_on_mouse_entered)
	if mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.disconnect(_on_mouse_exited)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.15)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15)
	await tween.finished
	queue_free()
