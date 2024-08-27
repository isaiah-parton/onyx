package onyx

import "core:fmt"
import "core:math/linalg"

Container_Info :: struct {
	size: [2]f32,
	box:  Maybe(Box),
}

Container :: struct {
	id:                       Id,
	active:                   bool,
	no_scroll_x, no_scroll_y: bool,
	scroll_x, scroll_y:       bool,
	desired_scroll:           [2]f32,
	scroll:                   [2]f32,
	scroll_time:              [2]f32,
	size:                     [2]f32,
	box:                      Box,
	dead:                     bool,
}

begin_container :: proc(info: Container_Info, loc := #caller_location) -> bool {
	id := hash(loc)
	cnt, ok := core.container_map[id]
	if !ok {
		cnt = new(Container)
		core.container_map[id] = cnt
	}

	cnt.id = id
	cnt.dead = false
	cnt.size = linalg.max(cnt.size, info.size)
	cnt.box = info.box.? or_else next_widget_box({})

	cnt.active = core.active_container == cnt.id
	if point_in_box(core.mouse_pos, cnt.box) && core.hovered_layer == current_layer().?.id {
		core.next_active_container = id
	}

	// Minimum size
	cnt.size = linalg.max(
		cnt.size,
		box_size(cnt.box) - cnt.scroll_time.yx * core.style.shape.scrollbar_thickness,
	)

	// Mouse wheel input
	if cnt.active {
		cnt.desired_scroll -= core.mouse_scroll * 100
	}

	append_draw_call(current_layer().?.index)
	push_clip(cnt.box)
	push_stack(&core.container_stack, cnt)

	draw_rounded_box_stroke(cnt.box, core.style.shape.rounding, 1, core.style.color.substance)

	layout_pos := cnt.box.lo - linalg.floor(cnt.scroll)
	layout_size := linalg.max(cnt.size, info.size)
	begin_layout({box = Box{layout_pos, layout_pos + layout_size}})

	return true
}

end_container :: proc() {

	cnt := current_container().?
	layout := current_layout().?
	cnt.size = layout.content_size + layout.spacing_size

	//TODO: Remove this
	// draw_text(
	// 	cnt.box.lo,
	// 	{text = fmt.tprintf("%.1f", box_size(cnt.box)), font = core.style.fonts[.Light], size = 20},
	// 	{255, 255, 255, 255},
	// )
	// draw_text(
	// 	cnt.box.lo + {0, 20},
	// 	{text = fmt.tprintf("%.1f", cnt.size), font = core.style.fonts[.Light], size = 20},
	// 	{255, 255, 255, 255},
	// )
	// draw_text(
	// 	cnt.box.lo + {0, 40},
	// 	{text = fmt.tprintf("%.1f", cnt.scroll), font = core.style.fonts[.Light], size = 20},
	// 	{255, 255, 255, 255},
	// )

	// Clamp scroll
	cnt.desired_scroll = linalg.max(
		linalg.min(cnt.desired_scroll, cnt.size - (cnt.box.hi - cnt.box.lo)),
		0,
	)
	delta_scroll := (cnt.desired_scroll - cnt.scroll) * core.delta_time * 15
	cnt.scroll += delta_scroll

	cnt.scroll_x = cnt.size.x > box_width(cnt.box) && !cnt.no_scroll_x
	cnt.scroll_y = cnt.size.y > box_height(cnt.box) && !cnt.no_scroll_y

	cnt.scroll_time.x = animate(cnt.scroll_time.x, 0.2, cnt.scroll_x)
	cnt.scroll_time.y = animate(cnt.scroll_time.y, 0.2, cnt.scroll_y)

	if abs(delta_scroll.x) > 0.1 || abs(delta_scroll.y) > 0.1 {
		core.draw_next_frame = true
	}

	end_layout()

	inner_box := shrink_box(cnt.box, 2)
	if cnt.scroll_y {
		box := get_box_cut_right(
			inner_box,
			cnt.scroll_time.y * core.style.shape.scrollbar_thickness,
		)
		if cnt.scroll_x {
			box.hi.y -= cnt.scroll_time.x * core.style.shape.scrollbar_thickness
		}
		if pos, ok := do_scrollbar({vertical = true, box = box, pos = cnt.scroll.y, travel = cnt.size.y - box_height(cnt.box), handle_size = box_height(box) * box_height(cnt.box) / cnt.size.y}).pos.?;
		   ok {
			cnt.scroll.y = pos
			cnt.desired_scroll.y = pos
		}
	}
	if cnt.scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			cnt.scroll_time.x * core.style.shape.scrollbar_thickness,
		)
		if cnt.scroll_y {
			box.hi.x -= cnt.scroll_time.y * core.style.shape.scrollbar_thickness
		}
		if pos, ok := do_scrollbar({box = box, pos = cnt.scroll.x, travel = cnt.size.x - box_width(cnt.box), handle_size = box_width(box) * box_width(cnt.box) / cnt.size.x}).pos.?;
		   ok {
			cnt.scroll.x = pos
			cnt.desired_scroll.x = pos
		}
	}

	pop_clip()
	pop_stack(&core.container_stack)
}

current_container :: proc() -> Maybe(^Container) {
	if core.container_stack.height > 0 {
		return core.container_stack.items[core.container_stack.height - 1]
	}
	return nil
}

push_clip :: proc(box: Box) {
	push_stack(&core.clip_stack, box)

	if core.current_draw_call != nil {
		core.current_draw_call.clip_box = box
		return
	}
	append_draw_call(current_layer().?.index)
}

pop_clip :: proc() {
	pop_stack(&core.clip_stack)

	if layer, ok := current_layer().?; ok {
		append_draw_call(current_layer().?.index)
	}
}

current_clip :: proc() -> Maybe(Box) {
	if core.clip_stack.height > 0 {
		return core.clip_stack.items[core.clip_stack.height - 1]
	}
	return nil
}

@(deferred_out = __do_container)
do_container :: proc(info: Container_Info, loc := #caller_location) -> (ok: bool) {
	return begin_container(info, loc)
}

@(private)
__do_container :: proc(ok: bool) {
	if ok {
		end_container()
	}
}
