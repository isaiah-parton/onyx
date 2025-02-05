package onyx

import "../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:reflect"

Container :: struct {
	using object:    ^Object,
	pan_offset:      [2]f32,
	target_scroll:   [2]f32,
	scroll:          [2]f32,
	scroll_time:     [2]f32,
	space:           [2]f32,
	space_needed:    [2]f32,
	hide_scrollbars: bool,
	min_zoom:        f32,
	max_zoom:        f32,
	zoom:            f32,
	target_zoom:     f32,
	is_active:       bool,
	swap_axis:       bool,
	enable_zoom:     bool,
	initialized:     bool,
}

solve_anchored_zoom_scroll :: proc(content_box, view_box: Box, old_zoom, new_zoom: f32, anchor: [2]f32) -> [2]f32 {
	content_origin := content_box.lo
	content_size := box_size(content_box)
	view_top_left := view_box.lo
	view_size := box_size(view_box)
	view_coordinates := (anchor - view_top_left) / view_size
	content_coordinates := (anchor - content_origin) / content_size
	coordinate_quotient := view_coordinates / content_coordinates
	area_difference := ((content_size / old_zoom) * new_zoom) - content_size
	return (area_difference / coordinate_quotient) * view_coordinates
}

begin_container :: proc(
	space: Maybe([2]f32) = nil,
	can_zoom: bool = false,
	hide_scrollbars: bool = false,
	loc := #caller_location,
) -> bool {
	object := get_object(hash(loc))
	if object.variant == nil {
		object.variant = Container {
			object   = object,
			min_zoom = 0.1,
			max_zoom = 1.0,
			zoom = 1,
			target_zoom = 1,
		}
		object.state.input_mask = OBJECT_STATE_ALL
	}
	self := &object.variant.(Container)
	self.hide_scrollbars = hide_scrollbars

	push_id(self.id)

	self.isolated = true

	begin_object(self) or_return

	self.box = next_box({})

	if point_in_box(mouse_point(), self.box) {
		hover_object(object)
	}

	self.space = space.? or_else linalg.max(box_size(self.box), self.space_needed)
	self.space_needed = 0

	layout_size := self.space
	if can_zoom {
		layout_size *= self.zoom
	} else {
		self.zoom = 1
		self.target_zoom = 1
	}

	vgo.push_scissor(vgo.make_box(self.box, current_options().radius))
	push_clip(self.box)

	layout_box := self.box
	layout_box.hi -= self.scroll_time.yx * (global_state.style.scrollbar_thickness + 4)
	set_next_box(move_box(layout_box, -self.scroll))
	begin_layout(side = .Top, does_grow = true) or_return

	return true
}

end_container :: proc() {
	layout := current_layout().?
	object := current_object().?
	extras := &object.variant.(Container)
	extras.space_needed = linalg.max(layout.content_size + layout.spacing_size * axis_normal(axis_of_side(current_options().side)), extras.space_needed)

	end_layout()

	pop_clip()
	vgo.pop_scissor()

	if .Hovered in object.state.current {
		if extras.enable_zoom &&
		   (.Pressed not_in object.state.current) &&
		   (key_down(.Left_Control) || key_down(.Right_Control)) {
			old_zoom := extras.target_zoom
			new_zoom := clamp(
				(math.round(old_zoom / 0.1) * 0.1) + global_state.mouse_scroll.y * 0.1,
				1,
				extras.max_zoom,
			)
			if new_zoom != old_zoom {
				extras.target_scroll += solve_anchored_zoom_scroll(layout.bounds, object.box, old_zoom, new_zoom, mouse_point())
			}
		} else {
			delta_scroll := global_state.mouse_scroll
			if key_down(.Left_Shift) || key_down(.Right_Shift) {
				delta_scroll.xy = delta_scroll.yx
			}
			// if self.swap_axis {
			// 	delta_scroll.xy = delta_scroll.yx
			// }
			extras.target_scroll -= delta_scroll * 100
		}
	}

	if false {
		extras.target_zoom = clamp(extras.target_zoom, extras.min_zoom, extras.max_zoom)
		delta_zoom := extras.target_zoom - extras.zoom
		if abs(delta_zoom) > 0.001 {
			draw_frames(1)
		}
		extras.zoom += delta_zoom * 15 * global_state.delta_time
	}

	content_size := extras.space * extras.zoom
	target_content_size := extras.space * extras.target_zoom
	view_size := box_size(object.box)

	extras.target_scroll = linalg.max(linalg.min(extras.target_scroll, target_content_size - view_size), 0)
	delta_scroll := (extras.target_scroll - extras.scroll) * global_state.delta_time * 15
	extras.scroll += delta_scroll

	if abs(delta_scroll.x) > 0.01 || abs(delta_scroll.y) > 0.01 {
		draw_frames(1)
	}

	enable_scroll_x := math.floor(content_size.x) > box_width(object.box) && !extras.hide_scrollbars
	enable_scroll_y := math.floor(content_size.y) > box_height(object.box) && !extras.hide_scrollbars

	extras.scroll_time.x = animate(extras.scroll_time.x, 0.2, enable_scroll_x)
	extras.scroll_time.y = animate(extras.scroll_time.y, 0.2, enable_scroll_y)

	display_scroll_x := extras.scroll_time.x > 0.0
	display_scroll_y := extras.scroll_time.y > 0.0

	inner_box := shrink_box(object.box, 4)

	if display_scroll_y {
		box := get_box_cut_right(
			inner_box,
			extras.scroll_time.y * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_x {
			box.hi.y -= extras.scroll_time.x * global_state.style.shape.scrollbar_thickness
		}
		if scrollbar(
			vertical = true,
			box = box,
			pos = &extras.scroll.y,
			travel = content_size.y - box_height(object.box),
			handle_size = max(box_height(box) * box_height(object.box) / content_size.y, global_state.style.scrollbar_thickness * 2),
		) {
			extras.target_scroll.y = extras.scroll.y
		}
	}

	if display_scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			extras.scroll_time.x * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_y {
			box.hi.x -= extras.scroll_time.y * global_state.style.shape.scrollbar_thickness
		}
		if scrollbar(
			box = box,
			pos = &extras.scroll.x,
			travel = content_size.x - box_width(object.box),
			handle_size = max(box_width(box) * box_width(object.box) / content_size.x, global_state.style.scrollbar_thickness * 2),
		) {
			extras.target_scroll.x = extras.scroll.x
		}
	}

	end_object()
	pop_id()
}

scrollbar :: proc(
	pos: ^f32,
	travel, handle_size: f32,
	box: Box,
	make_visible: bool = false,
	vertical: bool = false,
	loc := #caller_location,
) -> (changed: bool) {
	if pos == nil {
		return
	}
	object := get_object(hash(loc))
	object.flags += {.Sticky_Press, .Sticky_Hover}
	object.state.output_mask = {}
	if begin_object(object) {
		defer end_object()

		object.box = box

		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}

		i := int(vertical)
		j := 1 - i

		rounding := (object.box.hi[j] - object.box.lo[j]) / 2

		handle_time := pos^ / travel
		handle_travel_distance := (object.box.hi[i] - object.box.lo[i]) - handle_size

		handle_box: Box
		handle_box.lo[i] = object.box.lo[i] + max(0, handle_travel_distance * handle_time)
		handle_box.hi[i] = min(handle_box.lo[i] + handle_size, object.box.hi[i])
		handle_box.lo[j] = object.box.lo[j]
		handle_box.hi[j] = object.box.hi[j]

		if object_is_visible(object) {
			vgo.fill_box(
				handle_box,
				rounding,
				paint = style().color.accent if .Hovered in object.state.current else style().color.button,
			)
		}

		if .Pressed in object.state.current {
			if .Pressed not_in object.state.previous {
				global_state.drag_offset = handle_box.lo - mouse_point()
			}
			time := ((mouse_point()[i] + global_state.drag_offset[i]) - object.box.lo[i]) / handle_travel_distance
			pos^ = travel * clamp(time, f32(0), f32(1))
			changed = true
		}
	}
	return
}
