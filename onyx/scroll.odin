package onyx

import "core:fmt"
import "core:math/linalg"

Scrollbar_Info :: struct {
	using _:     Generic_Widget_Info,
	vertical:    bool,
	pos:         f32,
	handle_size: f32,
}

Scrollbar_Result :: struct {
	using _: Generic_Widget_Result,
	pos:     f32,
}

make_scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Info {
	info := info
	info.id = hash(loc)
	info.desired_size[1 - int(info.vertical)] = core.style.shape.scrollbar_thickness
	return info
}

add_scrollbar :: proc(info: Scrollbar_Info) -> (result: Scrollbar_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	widget.draggable = true

	i, j := int(info.vertical), 1 - int(info.vertical)

	rounding := (widget.box.hi[j] - widget.box.lo[j]) / 2

	draw_rounded_box_fill(widget.box, rounding, core.style.color.background)

	handle_box := Box{}

	travel := (widget.box.hi[i] - widget.box.lo[i]) - info.handle_size

	handle_box.lo[i] = widget.box.lo[i] + info.pos * travel
	handle_box.hi[i] = handle_box.lo[i] + info.handle_size

	handle_box.lo[j] = widget.box.lo[j]
	handle_box.hi[j] = widget.box.hi[j]

	draw_rounded_box_fill(handle_box, rounding, core.style.color.substance)

	if point_in_box(core.mouse_pos, handle_box) {
		widget.try_hover = true
	}

	end_widget()
	return
}

do_scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Result {
	return add_scrollbar(make_scrollbar(info, loc))
}

Scroll_Zone_Info :: struct {
	using _:                  Layer_Info,
	no_scroll_x, no_scroll_y: bool,
}

begin_scroll_zone :: proc(info: Scroll_Zone_Info, loc := #caller_location) {
	info := info
	info.id = hash(loc)
	info.parent = current_layer().?
	info.box = next_widget_box({})
	info.kind = .Background
	begin_layer(info)

	begin_layout({box = layout_box()})
	shrink(1)
	if !info.no_scroll_x {
		set_side(.Bottom)
		set_height_auto()
		set_width_fill()
		do_scrollbar({})
	}
	if !info.no_scroll_y {
		set_side(.Right)
		set_width_auto()
		set_height_fill()
		do_scrollbar({vertical = true})
	}
	end_layout()

	draw_rounded_box_stroke(layout_box(), core.style.shape.rounding, 1, core.style.color.substance)
}

end_scroll_zone :: proc() {
	end_layer()
}

@(deferred_out = __do_scroll_zone)
do_scroll_zone :: proc(info: Scroll_Zone_Info, loc := #caller_location) -> (ok: bool) {
	begin_scroll_zone(info, loc)
	return true
}

@(private)
__do_scroll_zone :: proc(ok: bool) {
	end_scroll_zone()
}

Container_Info :: struct {
	size: [2]f32,
	box:  Maybe(Box),
}

Container :: struct {
	id:                       Id,
	active:                   bool,
	no_scroll_x, no_scroll_y: bool,
	desired_scroll: [2]f32,
	scroll:                   [2]f32,
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
	cnt.size = linalg.max(cnt.size, info.size)
	cnt.box = info.box.? or_else next_widget_box({})

	cnt.active = core.active_container == cnt.id
	if point_in_box(core.mouse_pos, cnt.box) && core.hovered_layer == current_layer().?.id {
		core.next_active_container = id
	}

	if cnt.active {
		cnt.desired_scroll -= core.mouse_scroll * 8.5
	}
	cnt.desired_scroll = linalg.clamp(cnt.desired_scroll, 0, cnt.size - (cnt.box.hi - cnt.box.lo))
	delta_scroll := (cnt.desired_scroll - cnt.scroll) * core.delta_time * 15
	cnt.scroll += delta_scroll
	if abs(delta_scroll.x) >= 1 || abs(delta_scroll.y) >= 1 {
		core.draw_next_frame = true
	}

	push_clip(cnt.box)
	push_stack(&core.container_stack, cnt)

	draw_rounded_box_stroke(cnt.box, core.style.shape.rounding, 1, core.style.color.substance)

	layout_pos := cnt.box.lo - linalg.floor(cnt.scroll)
	layout_size := linalg.max(cnt.size, info.size)
	cnt.size = 0
	begin_layout({box = Box{layout_pos, layout_pos + layout_size}})

	return true
}

end_container :: proc() {

	cnt := current_container().?
	layout := current_layout().?
	cnt.size = layout.content_size + layout.spacing_size

	end_layout()

	begin_layout({box = shrink_box(cnt.box, 1)})
	if !cnt.no_scroll_y {

	}
	if !cnt.no_scroll_x {

	}
	end_layout()

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

	if core.current_draw_call != nil && core.current_draw_call.clip_box == view_box() {
		core.current_draw_call.clip_box = box
		return
	}
	append_draw_call(current_layer().?.index)
	core.current_draw_call.texture = core.font_atlas.texture
	core.current_draw_call.clip_box = box
}

pop_clip :: proc() {
	pop_stack(&core.clip_stack)

	append_draw_call(current_layer().?.index)
	core.current_draw_call.texture = core.font_atlas.texture
	core.current_draw_call.clip_box = current_clip().? or_else view_box()
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
