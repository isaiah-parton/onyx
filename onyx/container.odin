package onyx

import "../../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:reflect"

Container :: struct {
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
	enable_zoom:     bool,
	initialized:     bool,
}

zoom_container_anchored :: proc(widget: ^Widget, new_zoom: f32, anchor: [2]f32) {
	container := widget.variant.(Container)
	layout := current_layout().?
	content_top_left := layout.original_box.lo
	content_size := box_size(layout.original_box)
	view_top_left := widget.box.lo
	view_size := box_size(widget.box)
	view_coordinates := (anchor - view_top_left) / view_size
	content_coordinates := (anchor - content_top_left) / content_size
	coordinate_quotient := view_coordinates / content_coordinates
	area_difference := (container.space * new_zoom) - (container.space * container.target_zoom)
	container.target_scroll += (area_difference / coordinate_quotient) * view_coordinates
	container.target_zoom = new_zoom
}

begin_container :: proc(
	space: Maybe([2]f32) = nil,
	can_zoom: bool = false,
	loc := #caller_location,
) -> bool {
	widget := get_widget(hash(loc))

	if widget.variant == nil {
		widget.variant = Container {
			min_zoom = 0.1,
			max_zoom = 1.0,
		}
		widget.in_state_mask = WIDGET_STATE_ALL
	}

	begin_widget(widget) or_return

	container := widget.variant.(Container)

	is_active := .Hovered in (widget.state + widget.last_state)

	// TODO: Remove/fix this
	// if force_aspect_ratio {
	// 	size = size_ratio(size, box_size(widget.box))
	// }

	// Hover
	if point_in_box(global_state.mouse_pos, widget.box) {
		hover_widget(widget)
	}

	// Minimum size
	container.space = space.? or_else linalg.max(box_size(widget.box), container.space_needed)
	container.space_needed = 0

	// Determine layout size
	layout_size := container.space
	if can_zoom {
		layout_size *= container.zoom
	} else {
		container.zoom = 1
		container.target_zoom = 1
	}

	// Pre-draw controls
	if is_active {
		// Mouse panning
		if .Pressed in widget.state {
			if .Pressed not_in widget.last_state {
				container.pan_offset = global_state.mouse_pos - (widget.box.lo - container.scroll)
			}
			//
			new_scroll := linalg.clamp(
				widget.box.lo - (global_state.mouse_pos - container.pan_offset),
				0,
				layout_size - box_size(widget.box),
			)
			container.scroll = new_scroll
			container.target_scroll = new_scroll
		}
	}

	// Push draw scissor
	vgo.push_scissor(vgo.make_box(widget.box, global_state.style.rounding))

	// Determine layout box
	layout_origin := widget.box.lo - linalg.max(linalg.floor(container.scroll), 0)
	layout_box := Box{layout_origin, layout_origin + linalg.max(layout_size, box_size(widget.box))}

	begin_layout(layout_box, isolated = true) or_return

	set_side(.Top)

	return true
}

end_container :: proc() {
	widget := current_widget().?
	layout := current_layout().?
	container := widget.variant.(Container)
	// Update needed space
	container.space_needed = linalg.max(
		layout.content_size + layout.spacing_size,
		container.space_needed,
	)
	// Controls
	// if is_active {
	// 	if enable_zoom &&
	// 	   (.Pressed not_in widget.state) &&
	// 	   (key_down(.Left_Control) || key_down(.Right_Control)) {
	// 		// Determine old and new zoom levels
	// 		old_zoom := container.target_zoom
	// 		new_zoom := clamp(
	// 			(math.round(old_zoom / 0.1) * 0.1) + core.mouse_scroll.y * 0.1,
	// 			1,
	// 			container.max_zoom,
	// 		)
	// 		// Change needed?
	// 		if new_zoom != old_zoom {
	// 			zoom_container_anchored(info, new_zoom, core.mouse_pos)
	// 		}
	// 	} else {
	// 		delta_scroll := core.mouse_scroll
	// 		if key_down(.Left_Shift) || key_down(.Right_Shift) {
	// 			delta_scroll.xy = delta_scroll.yx
	// 		}
	// 		if swap_axis {
	// 			delta_scroll.xy = delta_scroll.yx
	// 		}
	// 		container.target_scroll -= delta_scroll * 100
	// 	}
	// }
	// Update zoom
	if false {
		container.target_zoom = clamp(
			container.target_zoom,
			container.min_zoom,
			container.max_zoom,
		)
		delta_zoom := container.target_zoom - container.zoom
		// Hint next frame to be drawn if delta sufficient
		if abs(delta_zoom) > 0.001 {
			global_state.draw_next_frame = true
		}
		container.zoom += delta_zoom * 15 * global_state.delta_time
	}
	// Update scroll
	content_size := container.space * container.zoom
	target_content_size := container.space * container.target_zoom
	view_size := box_size(widget.box)
	// Clamp target scroll
	container.target_scroll = linalg.clamp(
		container.target_scroll,
		0,
		target_content_size - view_size,
	)
	delta_scroll := (container.target_scroll - container.scroll) * global_state.delta_time * 15
	container.scroll += delta_scroll
	// Hint next frame to be drawn if delta sufficient
	if abs(delta_scroll.x) > 0.01 || abs(delta_scroll.y) > 0.01 {
		global_state.draw_next_frame = true
	}
	// Enable/disable scrollbars
	enable_scroll_x :=
		math.floor(content_size.x) > box_width(widget.box) && !container.hide_scrollbars
	enable_scroll_y :=
		math.floor(content_size.y) > box_height(widget.box) && !container.hide_scrollbars
	// Animate scrollbars
	container.scroll_time.x = animate(container.scroll_time.x, 0.2, enable_scroll_x)
	container.scroll_time.y = animate(container.scroll_time.y, 0.2, enable_scroll_y)
	// Enable/disable them for real this time
	display_scroll_x := container.scroll_time.x > 0.0
	display_scroll_y := container.scroll_time.y > 0.0
	// Scrollbars
	inner_box := shrink_box(widget.box, 4)
	push_id(widget.id)
	if display_scroll_y {
		box := get_box_cut_right(
			inner_box,
			container.scroll_time.y * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_x {
			box.hi.y -= container.scroll_time.x * global_state.style.shape.scrollbar_thickness
		}
		// if scrollbar({make_visible = (is_active || abs(delta_scroll.y) > 0.01), vertical = true, box = box, pos = &container.scroll.y, travel = content_size.y - box_height(widget.box), handle_size = box_height(box) * box_height(widget.box) / content_size.y}).changed {
		// 	container.target_scroll.y = container.scroll.y
		// }
	}
	if display_scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			container.scroll_time.x * global_state.style.shape.scrollbar_thickness,
		)
		if display_scroll_y {
			box.hi.x -= container.scroll_time.y * global_state.style.shape.scrollbar_thickness
		}
		// if scrollbar({make_visible = (is_active || abs(delta_scroll.x) > 0.01), box = box, pos = &container.scroll.x, travel = content_size.x - box_width(widget.box), handle_size = box_width(box) * box_width(widget.box) / content_size.x}).changed {
		// 	container.target_scroll.x = container.scroll.x
		// }
	}
	end_layout()
	vgo.pop_scissor()
	end_widget()
	pop_id()
}
