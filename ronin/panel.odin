package ronin

import kn "local:katana"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Panel :: struct {
	layer:            ^Layer,
	box:              Box,
	move_offset:      [2]f32,
	last_min_size:    [2]f32,
	min_size:         [2]f32,
	resize_offset:    [2]f32,
	non_snapped_size: [2]f32,
	control_animation_time: f32,
	moving:           bool,
	resizing:         bool,
	resize_side: Side,
	is_snapped:       bool,
	can_move:         bool,
	can_resize:       bool,
	dead:             bool,
}

Panel_Property :: union {
	Defined_Position,
	Defined_Size,
	Defined_Box,
	Panel_Can_Resize,
	Panel_Can_Snap,
	Layer_Sort_Method,
}

create_panel :: proc(id: Id) -> Maybe(^Panel) {
	for i in 0 ..< len(global_state.panels) {
		if global_state.panels[i] == nil {
			global_state.panels[i] = Panel{}
			global_state.panel_map[id] = &global_state.panels[i].?
			return &global_state.panels[i].?
		}
	}
	return nil
}

begin_panel :: proc(
	props: ..Panel_Property,
	loc := #caller_location,
) -> bool {
	MIN_SIZE :: [2]f32{100, 100}

	id := hash(loc)
	push_id(id)

	starting_box: Maybe(Box)
	starting_size: [2]f32
	starting_position: Maybe([2]f32)
	sort_method: Layer_Sort_Method = .Floating

	self, ok := global_state.panel_map[id]
	if !ok {
		self = create_panel(id).? or_return
	}

	for prop in props {
		#partial switch v in prop {
		case Defined_Box:
			starting_box = Box(v)
		case Defined_Size:
			starting_size = ([2]f32)(v)
		case Defined_Position:
			starting_position = ([2]f32)(v)
		case Panel_Can_Resize:
			self.can_resize = bool(v)
		case Layer_Sort_Method:
			sort_method = v
		}
	}

	if !ok {
		if starting_box, ok := starting_box.?; ok {
			self.box = starting_box
		} else {
			position := starting_position.? or_else get_next_panel_position()
			size := linalg.max(starting_size, MIN_SIZE)
			self.box = {position, position + size}
		}

		self.can_move = true
		self.can_resize = true
	}

	style := get_current_style()

	push_stack(&global_state.panel_stack, self)

	if self.moving == true {
		mouse_point := mouse_point()
		size := self.box.hi - self.box.lo
		self.box.lo = mouse_point - self.move_offset
		self.box.hi = self.box.lo + size
		global_state.panel_snapping.active_panel = self
		draw_frames(1)
	}

	min_size := linalg.max(MIN_SIZE, self.min_size)
	if self.resizing {
		self.resizing = false
		switch self.resize_side {
		case .Bottom:
			self.box.hi.y = max(mouse_point().y, self.box.lo.y + self.min_size.y)
		case .Top:
			self.box.lo.y = min(mouse_point().y, self.box.hi.y - self.min_size.y)
		case .Left:
			self.box.lo.x = min(mouse_point().x, self.box.hi.x - self.min_size.x)
		case .Right:
			self.box.hi.x = max(mouse_point().x, self.box.lo.x + self.min_size.x)
		}
	} else {
		if self.can_resize {
			self.box.hi = linalg.max(self.box.hi, self.box.lo + min_size)
		} else {
			self.box.hi = self.box.lo + min_size
		}
	}
	self.box = snapped_box(self.box)

	if self.last_min_size != self.min_size {
		draw_frames(1)
	}

	self.last_min_size = linalg.max(self.min_size, MIN_SIZE)
	self.min_size = {}

	begin_layer(sort_method) or_return
	self.layer = current_layer().?

	rounding := f32(1 - int(self.is_snapped)) * style.rounding

	object := get_object(hash("panelbg"))
	object.flags += {.Sticky_Hover, .Sticky_Press}
	object.state.input_mask = OBJECT_STATE_ALL
	set_next_box(self.box)
	begin_object(object) or_return

	if object.variant == nil {
		object.state.input_mask = OBJECT_STATE_ALL
	}

	if point_in_box(mouse_point(), object.box) {
		hover_object(object)
	}

	enable_controls := (key_down(.Left_Alt) || mouse_down(.Middle)) && (.Hovered in object.state.current)

	if enable_controls {
		if .Clicked in object.state.current && object.click.count == 2 {
			self.box.hi = self.box.lo + self.last_min_size
		} else if object_is_dragged(object, beyond = 100 if self.is_snapped else 0, with = .Middle) {
			if !self.moving {
				if self.is_snapped {
					self.box.lo = mouse_point() - self.non_snapped_size / 2
					self.box.hi = mouse_point() + self.non_snapped_size / 2
					self.is_snapped = false
				}
				self.non_snapped_size = box_size(self.box)
			}
			self.moving = true
			self.move_offset = global_state.mouse_pos - self.box.lo
		}
	}

	if !self.is_snapped {
		if kn.disable_scissor() {
			kn.add_box_shadow(
				self.box,
				rounding,
				6,
				style.color.shadow,
			)
		}
	}

	if .Pressed not_in object.state.current {
		self.moving = false
	}

	self.control_animation_time = animate(self.control_animation_time, 0.15, self.moving || self.resizing)

	kn.push_scissor(kn.make_box(self.box, rounding))
	push_clip(self.box)

	kn.add_box(object.box, paint = style.color.foreground)

	begin_layout(as_column, is_root, with_box(self.box)) or_return
	return true
}

end_panel :: proc() {
	layout := get_current_layout()
	end_object()
	end_layout()
	pop_clip()

	self := current_panel()

	self.min_size += layout.content_size + layout.spacing_size

	style := get_current_style()

	kn.add_box_lines(self.box, style.line_width, style.rounding, paint = kn.mix(self.control_animation_time, style.color.lines, style.color.accent))
	kn.add_box(self.box, paint = kn.fade(style.color.accent, 0.1 * self.control_animation_time))

	if self.can_resize {
		zone_width := f32(2)
		zones: [Side]Box = {
			.Left = {{self.box.lo.x - zone_width, self.box.lo.y}, {self.box.lo.x + zone_width, self.box.hi.y}},
			.Right = {{self.box.hi.x - zone_width, self.box.lo.y}, {self.box.hi.x + zone_width, self.box.hi.y}},
			.Top = {{self.box.lo.x, self.box.lo.y - zone_width}, {self.box.hi.x, self.box.lo.y + zone_width}},
			.Bottom = {{self.box.lo.x, self.box.hi.y - zone_width}, {self.box.hi.x, self.box.hi.y + zone_width}},
		}

		for side, side_index in Side {
			push_id(side_index)
			defer pop_id()
			zone := zones[side]
			object := get_object(hash("resize"))
			object.flags += {.Sticky_Hover, .Sticky_Press}
			set_next_box(zone)
			if do_object(object) {
				if point_in_box(mouse_point(), object.box) {
					hover_object(object)
				}
				if .Hovered in object.state.current {
					set_cursor(Mouse_Cursor(int(Mouse_Cursor.Resize_EW) + int(side) / 2))
				}
				kn.add_box(
					object.box,
					paint = kn.fade(style.color.accent, f32(int(.Hovered in object.state.current))),
				)
				if .Pressed in object.state.current {
					self.resizing = true
					self.resize_side = side
					if .Pressed not_in object.state.previous {
						self.resize_offset = self.box.lo - global_state.mouse_pos
					}
				}
			}
		}
	}

	pop_id()
	kn.pop_scissor()
	end_layer()
	pop_stack(&global_state.panel_stack)
}

@(deferred_out=__do_panel)
do_panel :: proc(props: ..Panel_Property, loc := #caller_location) -> bool {
	return begin_panel(..props, loc = loc)
}

@(private)
__do_panel :: proc(ok: bool) {
	if ok {
		end_panel()
	}
}

current_panel :: proc(loc := #caller_location) -> ^Panel {
	assert(global_state.panel_stack.height > 0, "There is no current panel!", loc)
	return global_state.panel_stack.items[global_state.panel_stack.height - 1]
}

get_next_panel_position :: proc() -> [2]f32 {
	pos: [2]f32 = 100
	for i in 0 ..< len(global_state.panels) {
		if panel, ok := global_state.panels[i].?; ok {
			if pos == panel.box.lo {
				pos += 50
			}
		}
	}
	return pos
}

Panel_Snap_State :: struct {
	active_panel: Maybe(^Panel),
	snaps:        [8]Panel_Snap,
	snap_count:   int,
}

Panel_Snap :: enum {
	Top,
	Bottom,
	Left,
	Right,
	Center,
}

reset_panel_snap_state :: proc(state: ^Panel_Snap_State) {
	state.active_panel = nil
}

draw_panel_snap_widgets :: proc(state: Panel_Snap_State) {
	if panel, ok := state.active_panel.?; ok {
		OFFSET_FROM_EDGE :: 20
		RADIUS :: 35

		Snap_Orb :: struct {
			position: [2]f32,
			box:      Box,
		}

		screen_size := global_state.view

		orbs: [5]Snap_Orb = {
			{
				position = {OFFSET_FROM_EDGE + RADIUS, screen_size.y / 2},
				box = {{}, {screen_size.x / 2, screen_size.y}},
			},
			{
				position = {screen_size.x - (OFFSET_FROM_EDGE + RADIUS), screen_size.y / 2},
				box = {{screen_size.x / 2, 0}, screen_size},
			},
			{
				position = {screen_size.x / 2, OFFSET_FROM_EDGE + RADIUS},
				box = {{}, {screen_size.x, screen_size.y / 2}},
			},
			{
				position = {screen_size.x / 2, screen_size.y - (OFFSET_FROM_EDGE + RADIUS)},
				box = {{0, screen_size.y / 2}, screen_size},
			},
			{position = screen_size / 2, box = view_box()},
		}

		for orb in orbs {
			distance_to_mouse := linalg.length(mouse_point() - orb.position)
			if distance_to_mouse <= RADIUS {
				kn.add_box_lines(orb.box, 2, paint = get_current_style().color.accent)
				if mouse_released(.Left) {
					panel.box = orb.box
					panel.is_snapped = true
				}
			} else {
				kn.add_circle(orb.position, RADIUS, kn.fade(get_current_style().color.accent, 0.5))
			}
		}
	}
}
