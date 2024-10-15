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
	using _:   Widget_Info,
	min_zoom:  f32,
	max_zoom:  f32,
	size:      [2]f32,
	mode:      Container_Mode,
	layout:    ^Layout,
	is_active: bool,
}

Container :: struct {
	active:             bool,
	scroll_x, scroll_y: bool,
	zoom:               f32,
	desired_scroll:     [2]f32,
	scroll:             [2]f32,
	scroll_time:        [2]f32,
	size:               [2]f32,
}

init_container :: proc(using info: ^Container_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

begin_container :: proc(using info: ^Container_Info) -> bool {
	if info == nil do return false
	begin_widget(info) or_return

	is_active = .Hovered in self.state

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	// Minimum size
	self.cont.size = linalg.max(self.cont.size, info.size, box_size(self.box))

	// Mouse wheel input
	if is_active {
		delta_scroll := core.mouse_scroll
		if key_down(.Left_Shift) || key_down(.Right_Shift) {
			delta_scroll.xy = delta_scroll.yx
		}
		self.cont.desired_scroll -= delta_scroll * 100
	}
	push_scissor(self.box, add_shape_box(self.box, core.style.rounding))

	layout_pos := self.box.lo - linalg.floor(self.cont.scroll)
	layout_size := linalg.max(self.cont.size, info.size)
	begin_layout({box = Box{layout_pos, layout_pos + layout_size}, isolated = true}) or_return

	layout = current_layout().?
	layout.next_cut_side = .Top

	return true
}

end_container :: proc(using info: ^Container_Info) {
	self.cont.size = linalg.max(layout.content_size + layout.spacing_size, self.cont.size)

	// Clamp scroll
	self.cont.desired_scroll = linalg.max(
		linalg.min(self.cont.desired_scroll, self.cont.size - (self.box.hi - self.box.lo)),
		0,
	)
	delta_scroll := (self.cont.desired_scroll - self.cont.scroll) * core.delta_time * 15
	self.cont.scroll += delta_scroll

	self.cont.scroll_x = self.cont.size.x > box_width(self.box)
	self.cont.scroll_y = self.cont.size.y > box_height(self.box)

	self.cont.scroll_time.x = animate(self.cont.scroll_time.x, 0.2, self.cont.scroll_x)
	self.cont.scroll_time.y = animate(self.cont.scroll_time.y, 0.2, self.cont.scroll_y)

	if abs(delta_scroll.x) > 0.1 || abs(delta_scroll.y) > 0.1 {
		core.draw_next_frame = true
	}

	end_layout()

	inner_box := shrink_box(self.box, 4)

	if self.cont.scroll_y {
		box := get_box_cut_right(
			inner_box,
			self.cont.scroll_time.y * core.style.shape.scrollbar_thickness,
		)
		if self.cont.scroll_x {
			box.hi.y -= self.cont.scroll_time.x * core.style.shape.scrollbar_thickness
		}
		if scrollbar({
			make_visible = self.cont.active || abs(delta_scroll.y) > 0.1,
			vertical = true,
			box = box,
			pos = &self.cont.scroll.y,
			travel = self.cont.size.y - box_height(self.box),
			handle_size = box_height(box) * box_height(self.box) / self.cont.size.y,
		}).changed {
			self.cont.desired_scroll.y = self.cont.scroll.y
		}
	}
	if self.cont.scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			self.cont.scroll_time.x * core.style.shape.scrollbar_thickness,
		)
		if self.cont.scroll_y {
			box.hi.x -= self.cont.scroll_time.y * core.style.shape.scrollbar_thickness
		}
		if scrollbar({
			make_visible = self.cont.active || abs(delta_scroll.x) > 0.1,
			box = box,
			pos = &self.cont.scroll.x,
			travel = self.cont.size.x - box_width(self.box),
			handle_size = box_width(box) * box_width(self.box) / self.cont.size.x,
		}).changed {
			self.cont.desired_scroll.x = self.cont.scroll.x
		}
	}

	// Table outline
	draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.style.color.substance)

	end_widget()
	pop_scissor()
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
