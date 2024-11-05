package onyx

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "../../vgo"

Container_Info :: struct {
	using _:            Widget_Info,
	// Optional required space for content
	space:              Maybe([2]f32),
	// Force the scrollable area to have a given aspect ratio
	force_aspect_ratio: bool,
	// Swap axis when scrolling with mouse wheel
	swap_axis:          bool,
	hide_scrollbars:    bool,
	// Zoom limits
	min_zoom:           f32,
	max_zoom:           f32,
	// Initial zoom/scroll
	initial_zoom:       Maybe(f32),
	initial_scroll:     Maybe([2]f32),
	// Scissor rounded corners
	corners:            Maybe([4]f32),
	// Navigation mode
	enable_zoom:        bool,
	// Transient layout reference
	layout:             ^Layout,
	// Self-managed values
	is_active:          bool,
	was_scrolled:       bool,
	was_zoomed:         bool,
}

Container :: struct {
	pan_offset:    [2]f32,
	target_scroll: [2]f32,
	scroll:        [2]f32,
	scroll_time:   [2]f32,
	space:         [2]f32,
	space_needed:  [2]f32,
	zoom:          f32,
	target_zoom:   f32,
	initialized:   bool,
}

init_container :: proc(using info: ^Container_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	sticky = true
	if enable_zoom {
		min_zoom = max(min_zoom, 0.1)
		max_zoom = max(max_zoom, min_zoom + 1.0)
	}
	if !self.cont.initialized {
		self.cont.initialized = true

		self.cont.zoom = clamp(initial_zoom.? or_else 1, min_zoom, max_zoom)
		self.cont.scroll = initial_scroll.? or_else {}

		self.cont.target_zoom = self.cont.zoom
		self.cont.target_scroll = self.cont.scroll
	}
	in_state_mask = WIDGET_STATE_ALL
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
	area_difference := (self.cont.space * new_zoom) - (self.cont.space * self.cont.target_zoom)
	// Update the target values
	self.cont.target_scroll += (area_difference / uv_quotient) * uv_view
	self.cont.target_zoom = new_zoom
}

begin_container :: proc(using info: ^Container_Info) -> bool {
	if info == nil do return false
	begin_widget(info) or_return

	is_active = .Hovered in (self.state + self.last_state)

	// TODO: Remove/fix this
	// if force_aspect_ratio {
	// 	size = size_ratio(size, box_size(self.box))
	// }

	// Hover
	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	// Minimum size
	self.cont.space = space.? or_else linalg.max(box_size(self.box), self.cont.space_needed)
	self.cont.space_needed = 0

	// Determine layout size
	layout_size := self.cont.space
	if enable_zoom {
		layout_size *= self.cont.zoom
	} else {
		self.cont.zoom = 1
		self.cont.target_zoom = 1
	}

	// Pre-draw controls
	if is_active {
		// Mouse panning
		if .Pressed in self.state {
			if .Pressed not_in self.last_state {
				self.cont.pan_offset = core.mouse_pos - (self.box.lo - self.cont.scroll)
			}
			//
			new_scroll := linalg.clamp(
				self.box.lo - (core.mouse_pos - self.cont.pan_offset),
				0,
				layout_size - box_size(self.box),
			)
			self.cont.scroll = new_scroll
			self.cont.target_scroll = new_scroll
			//
			was_scrolled = true
		}
	}

	// Push draw scissor
	vgo.push_scissor(vgo.make_box(self.box, corners.? or_else core.style.rounding))

	// Determine layout box
	layout_origin := self.box.lo - linalg.max(linalg.floor(self.cont.scroll), 0)
	layout_box := Box{layout_origin, layout_origin + linalg.max(layout_size, box_size(self.box))}

	begin_layout({box = layout_box, isolated = true}) or_return
	layout = current_layout().?
	set_side(.Top)

	return true
}

end_container :: proc(using info: ^Container_Info) {
	assert(info != nil)
	assert(info.self != nil)
	// Update needed space
	self.cont.space_needed = linalg.max(layout.content_size + layout.spacing_size, self.cont.space_needed)
	end_layout()
	// Controls
	if is_active {
		if enable_zoom &&
		   (.Pressed not_in self.state) &&
		   (key_down(.Left_Control) || key_down(.Right_Control)) {
			// Determine old and new zoom levels
			old_zoom := self.cont.target_zoom
			new_zoom := clamp((math.round(old_zoom / 0.1) * 0.1) + core.mouse_scroll.y * 0.1, 1, max_zoom)
			// Change needed?
			if new_zoom != old_zoom {
				zoom_container_anchored(info, new_zoom, core.mouse_pos)
			}
		} else {
			delta_scroll := core.mouse_scroll
			if key_down(.Left_Shift) || key_down(.Right_Shift) {
				delta_scroll.xy = delta_scroll.yx
			}
			if swap_axis {
				delta_scroll.xy = delta_scroll.yx
			}
			self.cont.target_scroll -= delta_scroll * 100
		}
	}
	// Update zoom
	if enable_zoom {
		self.cont.target_zoom = clamp(self.cont.target_zoom, min_zoom, max_zoom)
		delta_zoom := self.cont.target_zoom - self.cont.zoom
		// Hint next frame to be drawn if delta sufficient
		if abs(delta_zoom) > 0.001 {
			was_zoomed = true
			core.draw_next_frame = true
		}
		self.cont.zoom += delta_zoom * 15 * core.delta_time
	}
	// Update scroll
	content_size := self.cont.space * self.cont.zoom
	target_content_size := self.cont.space * self.cont.target_zoom
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
		was_scrolled = true
	}
	// Enable/disable scrollbars
	enable_scroll_x := math.floor(content_size.x) > box_width(self.box) && !hide_scrollbars
	enable_scroll_y := math.floor(content_size.y) > box_height(self.box) && !hide_scrollbars
	// Animate scrollbars
	self.cont.scroll_time.x = animate(self.cont.scroll_time.x, 0.2, enable_scroll_x)
	self.cont.scroll_time.y = animate(self.cont.scroll_time.y, 0.2, enable_scroll_y)
	// Enable/disable them for real this time
	display_scroll_x := self.cont.scroll_time.x > 0.0
	display_scroll_y := self.cont.scroll_time.y > 0.0
	// Scrollbars
	inner_box := shrink_box(self.box, 4)
	push_id(self.id)
	if display_scroll_y {
		box := get_box_cut_right(
			inner_box,
			self.cont.scroll_time.y * core.style.shape.scrollbar_thickness,
		)
		if display_scroll_x {
			box.hi.y -= self.cont.scroll_time.x * core.style.shape.scrollbar_thickness
		}
		if scrollbar({make_visible = (is_active || abs(delta_scroll.y) > 0.01), vertical = true, box = box, pos = &self.cont.scroll.y, travel = content_size.y - box_height(self.box), handle_size = box_height(box) * box_height(self.box) / content_size.y}).changed {
			self.cont.target_scroll.y = self.cont.scroll.y
		}
	}
	if display_scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			self.cont.scroll_time.x * core.style.shape.scrollbar_thickness,
		)
		if display_scroll_y {
			box.hi.x -= self.cont.scroll_time.y * core.style.shape.scrollbar_thickness
		}
		if scrollbar({make_visible = (is_active || abs(delta_scroll.x) > 0.01), box = box, pos = &self.cont.scroll.x, travel = content_size.x - box_width(self.box), handle_size = box_width(box) * box_width(self.box) / content_size.x}).changed {
			self.cont.target_scroll.x = self.cont.scroll.x
		}
	}
	pop_id()
	vgo.pop_scissor()
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
