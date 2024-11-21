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

zoom_container_anchored :: proc(self: ^Container, new_zoom: f32, anchor: [2]f32) {
	content_top_left := self.content.box.lo
	content_size := box_size(self.content.box)
	view_top_left := self.box.lo
	view_size := box_size(self.box)
	view_coordinates := (anchor - view_top_left) / view_size
	content_coordinates := (anchor - content_top_left) / content_size
	coordinate_quotient := view_coordinates / content_coordinates
	area_difference := (self.space * new_zoom) - (self.space * self.target_zoom)
	self.target_scroll += (area_difference / coordinate_quotient) * view_coordinates
	self.target_zoom = new_zoom
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
		}
		object.state.input_mask = OBJECT_STATE_ALL
	}

	begin_object(object) or_return

	self := object.variant.(Container)

	is_active := .Hovered in new_state(self.state)

	if point_in_box(global_state.mouse_pos, self.box) {
		hover_object(self)
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

	if is_active {
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

	layout_origin := self.box.lo - linalg.max(linalg.floor(self.scroll), 0)
	layout_box := Box{layout_origin, layout_origin + linalg.max(layout_size, box_size(self.box))}

	begin_layout(placement = layout_box) or_return

	return true
}

end_container :: proc() {
	end_layout()
	end_object()
	pop_id()
}

display_container :: proc(self: ^Container) {
	place_object(self)

	self.space_needed = linalg.max(space_required_by_object_content(self.content), self.space_needed)

	if self.is_active {
		if self.enable_zoom &&
		   (.Pressed not_in self.state.current) &&
		   (key_down(.Left_Control) || key_down(.Right_Control)) {
			// Determine old and new zoom levels
			old_zoom := self.target_zoom
			new_zoom := clamp(
				(math.round(old_zoom / 0.1) * 0.1) + global_state.mouse_scroll.y * 0.1,
				1,
				self.max_zoom,
			)
			// Change needed?
			if new_zoom != old_zoom {
				zoom_container_anchored(self, new_zoom, global_state.mouse_pos)
			}
		} else {
			delta_scroll := global_state.mouse_scroll
			if key_down(.Left_Shift) || key_down(.Right_Shift) {
				delta_scroll.xy = delta_scroll.yx
			}
			if self.swap_axis {
				delta_scroll.xy = delta_scroll.yx
			}
			self.target_scroll -= delta_scroll * 100
		}
	}
	// Update zoom
	if false {
		self.target_zoom = clamp(self.target_zoom, self.min_zoom, self.max_zoom)
		delta_zoom := self.target_zoom - self.zoom
		// Hint next frame to be drawn if delta sufficient
		if abs(delta_zoom) > 0.001 {
			draw_frames(1)
		}
		self.zoom += delta_zoom * 15 * global_state.delta_time
	}
	// Update scroll
	content_size := self.space * self.zoom
	target_content_size := self.space * self.target_zoom
	view_size := box_size(self.box)
	// Clamp target scroll
	self.target_scroll = linalg.clamp(self.target_scroll, 0, target_content_size - view_size)
	delta_scroll := (self.target_scroll - self.scroll) * global_state.delta_time * 15
	self.scroll += delta_scroll
	// Hint next frame to be drawn if delta sufficient
	if abs(delta_scroll.x) > 0.01 || abs(delta_scroll.y) > 0.01 {
		draw_frames(1)
	}
	// Enable/disable scrollbars
	enable_scroll_x := math.floor(content_size.x) > box_width(self.box) && !self.hide_scrollbars
	enable_scroll_y := math.floor(content_size.y) > box_height(self.box) && !self.hide_scrollbars
	// Animate scrollbars
	self.scroll_time.x = animate(self.scroll_time.x, 0.2, enable_scroll_x)
	self.scroll_time.y = animate(self.scroll_time.y, 0.2, enable_scroll_y)
	// Enable/disable them for real this time
	display_scroll_x := self.scroll_time.x > 0.0
	display_scroll_y := self.scroll_time.y > 0.0
	// Scrollbars
	inner_box := shrink_box(self.box, 4)
	push_id(self.id)
	if display_scroll_y {
		box := get_box_cut_right(
			inner_box,
			self.scroll_time.y * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_x {
			box.hi.y -= self.scroll_time.x * global_state.style.shape.scrollbar_thickness
		}
		// if scrollbar({make_visible = (is_active || abs(delta_scroll.y) > 0.01), vertical = true, box = box, pos = &container.scroll.y, travel = content_size.y - box_height(object.box), handle_size = box_height(box) * box_height(object.box) / content_size.y}).changed {
		// 	container.target_scroll.y = container.scroll.y
		// }
	}
	if display_scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			self.scroll_time.x * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_y {
			box.hi.x -= self.scroll_time.y * global_state.style.shape.scrollbar_thickness
		}
		// if scrollbar({make_visible = (is_active || abs(delta_scroll.x) > 0.01), box = box, pos = &container.scroll.x, travel = content_size.x - box_width(object.box), handle_size = box_width(box) * box_width(object.box) / content_size.x}).changed {
		// 	container.target_scroll.x = container.scroll.x
		// }
	}
	vgo.push_scissor(vgo.make_box(self.box, global_state.style.rounding))
	vgo.fill_box(self.box, paint = colors().field)
	for child in self.children {
		display_object(child)
	}
	vgo.pop_scissor()
}
