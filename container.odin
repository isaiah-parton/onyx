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
	loc := #caller_location,
) -> bool {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Container {
			object   = object,
			min_zoom = 0.1,
			max_zoom = 1.0,
			zoom = 1,
		}
		object.state.input_mask = OBJECT_STATE_ALL
	}
	self := &object.variant.(Container)

	push_id(self.id)

	self.isolated = true

	begin_object(self) or_return

	self.box = next_box({})

	self.space = space.? or_else linalg.max(box_size(self.box), self.space_needed)
	self.space_needed = 0

	layout_size := self.space
	if can_zoom {
		layout_size *= self.zoom
	} else {
		self.zoom = 1
		self.target_zoom = 1
	}

	if self.is_active {
		if .Pressed in self.state.current {
			if .Pressed not_in self.state.previous {
				self.pan_offset = global_state.mouse_pos - (self.box.lo - self.scroll)
			}
			new_scroll := linalg.clamp(
				self.box.lo - (global_state.mouse_pos - self.pan_offset),
				0,
				layout_size - box_size(self.box),
			)
			self.scroll = new_scroll
			self.target_scroll = new_scroll
		}
	}


	vgo.fill_box(self.box, paint = colors().field)

	vgo.push_scissor(vgo.make_box(self.box))
	push_clip(self.box)

	set_next_box(self.box)
	begin_layout(side = .Top, does_grow = true) or_return

	return true
}

end_container :: proc() {
	layout := current_layout().?
	object := current_object().?
	extras := &object.variant.(Container)
	extras.space_needed = linalg.max(layout.content_size, extras.space_needed)

	end_layout()

	pop_clip()
	vgo.pop_scissor()

	if point_in_box(mouse_point(), object.box) {
		hover_object(object, transparent = true)
	}

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

	extras.target_scroll = linalg.clamp(extras.target_scroll, 0, target_content_size - view_size)
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
			// make_visible = (self.is_active || abs(delta_scroll.y) > 0.01),
			vertical = true,
			box = box,
			pos = &extras.scroll.y,
			travel = content_size.y - box_height(object.box),
			handle_size = box_height(box) * box_height(object.box) / content_size.y,
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
			// make_visible = (extras.is_active || abs(delta_scroll.x) > 0.01),
			box = box,
			pos = &extras.scroll.x,
			travel = content_size.x - box_width(object.box),
			handle_size = box_width(box) * box_width(object.box) / content_size.x,
		) {
			extras.target_scroll.x = extras.scroll.x
		}
	}

	end_object()
	pop_id()
}
