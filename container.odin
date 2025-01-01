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
	content_top_left := self.box.lo
	content_size := self.content.size
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
	side: Side = .Top,
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
	self.placement = next_user_placement()
	self.clip_children = true
	self.content.side = side

	begin_object(self) or_return

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

	self.content.offset = -linalg.max(linalg.floor(self.scroll), 0)

	push_placement_options({})

	vgo.fill_box(self.box, paint = colors().field)

	return true
}

end_container :: proc() {
	pop_placement_options()

	self := &current_object().?.variant.(Container)
	self.space_needed = linalg.max(space_used_by_object_content(self.content), self.space_needed)

	end_object()
	pop_id()
}

display_container :: proc(self: ^Container) {
	if point_in_box(mouse_point(), self.box) {
		hover_object(self, transparent = true)
	}

	if .Hovered in self.state.current {
		if self.enable_zoom &&
		   (.Pressed not_in self.state.current) &&
		   (key_down(.Left_Control) || key_down(.Right_Control)) {
			old_zoom := self.target_zoom
			new_zoom := clamp(
				(math.round(old_zoom / 0.1) * 0.1) + global_state.mouse_scroll.y * 0.1,
				1,
				self.max_zoom,
			)
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
	if false {
		self.target_zoom = clamp(self.target_zoom, self.min_zoom, self.max_zoom)
		delta_zoom := self.target_zoom - self.zoom
		if abs(delta_zoom) > 0.001 {
			draw_frames(1)
		}
		self.zoom += delta_zoom * 15 * global_state.delta_time
	}

	content_size := self.space * self.zoom
	target_content_size := self.space * self.target_zoom
	view_size := box_size(self.box)

	self.target_scroll = linalg.clamp(self.target_scroll, 0, target_content_size - view_size)
	delta_scroll := (self.target_scroll - self.scroll) * global_state.delta_time * 15
	self.scroll += delta_scroll

	if abs(delta_scroll.x) > 0.01 || abs(delta_scroll.y) > 0.01 {
		draw_frames(1)
	}

	enable_scroll_x := math.floor(content_size.x) > box_width(self.box) && !self.hide_scrollbars
	enable_scroll_y := math.floor(content_size.y) > box_height(self.box) && !self.hide_scrollbars

	self.scroll_time.x = animate(self.scroll_time.x, 0.2, enable_scroll_x)
	self.scroll_time.y = animate(self.scroll_time.y, 0.2, enable_scroll_y)

	display_scroll_x := self.scroll_time.x > 0.0
	display_scroll_y := self.scroll_time.y > 0.0

	inner_box := shrink_box(self.box, 4)

	if display_scroll_y {
		box := get_box_cut_right(
			inner_box,
			self.scroll_time.y * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_x {
			box.hi.y -= self.scroll_time.x * global_state.style.shape.scrollbar_thickness
		}
		if scrollbar(
			// make_visible = (self.is_active || abs(delta_scroll.y) > 0.01),
			vertical = true,
			box = box,
			pos = &self.scroll.y,
			travel = content_size.y - box_height(self.box),
			handle_size = box_height(box) * box_height(self.box) / content_size.y,
		) {
			self.target_scroll.y = self.scroll.y
		}
	}

	if display_scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			self.scroll_time.x * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_y {
			box.hi.x -= self.scroll_time.y * global_state.style.shape.scrollbar_thickness
		}
		if scrollbar(
			// make_visible = (self.is_active || abs(delta_scroll.x) > 0.01),
			box = box,
			pos = &self.scroll.x,
			travel = content_size.x - box_width(self.box),
			handle_size = box_width(box) * box_width(self.box) / content_size.x,
		) {
			self.target_scroll.x = self.scroll.x
		}
	}
}
