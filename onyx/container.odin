package onyx

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Container_Mode :: enum {
	Scroll,
	Pan_Zoom,
}

Container_Info :: struct {
	using _:            Widget_Info,
	max_zoom:           f32,
	size:               [2]f32,
	force_aspect_ratio: bool,
	exact_size:         bool,
	enable_zoom:        bool,
	mode:               Container_Mode,
	layout:             ^Layout,
	is_active:          bool,
}

Container :: struct {
	active:        bool,
	target_scroll: [2]f32,
	scroll:        [2]f32,
	scroll_time:   [2]f32,
	size:          [2]f32,
	zoom:          f32,
	target_zoom:   f32,
}

init_container :: proc(using info: ^Container_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	enable_zoom = mode == .Pan_Zoom
	if enable_zoom {
		max_zoom = max(max_zoom, 1)
	}
	return true
}

zoom_container_anchored :: proc(using info: ^Container_Info, new_zoom: f32, anchor: [2]f32) {
	assert(info != nil)
	content_top_left := layout.bounds.lo
	content_size := box_size(layout.bounds)
	// For readability
	view_top_left := self.box.lo
	view_size := box_size(self.box)
	// UV of cursor in viewport space
	uv_view := (anchor - view_top_left) / view_size
	// UV of cursor in content space
	uv_content := (anchor - content_top_left) / content_size
	// Divide em
	uv_quotient := uv_view / uv_content
	// Get the difference in displayed content area between both zoom levels
	area_difference := (self.cont.size * new_zoom) - (self.cont.size * self.cont.target_zoom)
	// Update the target values
	self.cont.target_scroll += (area_difference / uv_quotient) * uv_view
	self.cont.target_zoom = new_zoom
}

begin_container :: proc(using info: ^Container_Info) -> bool {
	if info == nil do return false
	begin_widget(info) or_return

	is_active = .Hovered in self.state

	if force_aspect_ratio {
		size = size_ratio(size, box_size(self.box))
	}

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	// Minimum size
	self.cont.size = size if exact_size else linalg.max(box_size(self.box), self.cont.size, size)
	self.cont.zoom = max(self.cont.zoom, 1)

	// Determine layout box
	layout_origin := self.box.lo - self.cont.scroll
	layout_size := self.cont.size
	if enable_zoom {
		layout_size *= self.cont.zoom
	} else {
		self.cont.zoom = 1
		self.cont.target_zoom = 1
	}
	layout_box := Box{layout_origin, layout_origin + layout_size}

	begin_layout({box = layout_box, isolated = true}) or_return

	layout = current_layout().?
	layout.next_cut_side = .Top

	// Push draw scissor
	push_scissor(self.box, add_shape_box(self.box, core.style.rounding))

	return true
}

end_container :: proc(using info: ^Container_Info) {
	end_layout()
	// Update container size
	if !exact_size {
		self.cont.size = linalg.max(layout.content_size + layout.spacing_size, self.cont.size)
	}
	// Controls
	if is_active {
		if enable_zoom && (key_down(.Left_Control) || key_down(.Right_Control)) {
			// Determine old and new zoom levels
			old_zoom := self.cont.target_zoom
			new_zoom := clamp(old_zoom + core.mouse_scroll.y * 0.1, 1, max_zoom)
			// Change needed?
			if new_zoom != old_zoom {
				zoom_container_anchored(info, new_zoom, core.mouse_pos)
			}
		} else {
			delta_scroll := core.mouse_scroll
			if key_down(.Left_Shift) || key_down(.Right_Shift) {
				delta_scroll.xy = delta_scroll.yx
			}
			self.cont.target_scroll -= delta_scroll * 100
		}
	}
	// Update zoom
	if enable_zoom {
		self.cont.target_zoom = clamp(self.cont.target_zoom, 1, max_zoom)
		delta_zoom := self.cont.target_zoom - self.cont.zoom
		// Hint next frame to be drawn if delta sufficient
		if abs(delta_zoom) > 0.001 {
			core.draw_next_frame = true
		}
		self.cont.zoom += delta_zoom * 15 * core.delta_time
	}
	// Update scroll
	content_size := self.cont.size * self.cont.zoom
	target_content_size := self.cont.size * self.cont.target_zoom
	view_size := box_size(self.box)
	// Clamp target scroll
	self.cont.target_scroll = linalg.clamp(
		self.cont.target_scroll,
		0,
		target_content_size - view_size,
	)
	delta_scroll := (self.cont.target_scroll - self.cont.scroll) * core.delta_time * 15
	self.cont.scroll += delta_scroll
	// Hint next frame to be drawn if delta sufficient
	if abs(delta_scroll.x) > 0.01 || abs(delta_scroll.y) > 0.01 {
		core.draw_next_frame = true
	}
	// Enable/disable scrollbars
	enable_scroll_x := content_size.x > box_width(self.box)
	enable_scroll_y := content_size.y > box_height(self.box)
	// Animate scrollbars
	self.cont.scroll_time.x = animate(self.cont.scroll_time.x, 0.2, enable_scroll_x)
	self.cont.scroll_time.y = animate(self.cont.scroll_time.y, 0.2, enable_scroll_y)
	// Scrollbars
	inner_box := shrink_box(self.box, 4)
	push_id(self.id)
	if enable_scroll_y {
		box := get_box_cut_right(
			inner_box,
			self.cont.scroll_time.y * core.style.shape.scrollbar_thickness,
		)
		if enable_scroll_x {
			box.hi.y -= self.cont.scroll_time.x * core.style.shape.scrollbar_thickness
		}
		if scrollbar({make_visible = (self.cont.active || abs(delta_scroll.y) > 0.1), vertical = true, box = box, pos = &self.cont.scroll.y, travel = content_size.y - box_height(self.box), handle_size = box_height(box) * box_height(self.box) / content_size.y}).changed {
			self.cont.target_scroll.y = self.cont.scroll.y
		}
	}
	if enable_scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			self.cont.scroll_time.x * core.style.shape.scrollbar_thickness,
		)
		if enable_scroll_y {
			box.hi.x -= self.cont.scroll_time.y * core.style.shape.scrollbar_thickness
		}
		if scrollbar({make_visible = (self.cont.active || abs(delta_scroll.x) > 0.1), box = box, pos = &self.cont.scroll.x, travel = content_size.x - box_width(self.box), handle_size = box_width(box) * box_width(self.box) / content_size.x}).changed {
			self.cont.target_scroll.x = self.cont.scroll.x
		}
	}
	pop_id()
	// Table outline
	draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.style.color.substance)
	pop_scissor()
	end_widget()
}

@(deferred_in_out = __container)
container :: proc(info: ^Container_Info, loc := #caller_location) -> bool {
	init_container(info, loc) or_return
	return begin_container(info)
}

@(private)
__container :: proc(info: ^Container_Info, _: runtime.Source_Code_Location, ok: bool) {
	if ok {
		end_container(info)
	}
}
