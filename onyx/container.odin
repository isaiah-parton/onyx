package onyx

import "core:fmt"
import "core:math/linalg"

Container_Info :: struct {
	id:   Id,
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
	// Transient
	layout:                   ^Layout,
}

begin_container :: proc(info: Container_Info, loc := #caller_location) -> bool {
	id := info.id if info.id != 0 else hash(loc)
	self, ok := core.container_map[id]
	if !ok {
		self = new(Container)
		core.container_map[id] = self
		ok = true
	}
	if !ok do return false
	assert(self != nil)

	self.id = id
	self.dead = false
	self.box = info.box.? or_else next_widget_box(nil)

	self.active = core.active_container == self.id
	if point_in_box(core.mouse_pos, self.box) && core.hovered_layer == current_layer().?.id {
		core.next_active_container = id
	}

	// Minimum size
	self.size = linalg.max(self.size, info.size, box_size(self.box))

	// Mouse wheel input
	if self.active {
		delta_scroll := core.mouse_scroll
		if key_down(.Left_Shift) || key_down(.Right_Shift) {
			delta_scroll.xy = delta_scroll.yx
		}
		self.desired_scroll -= delta_scroll * 100
	}
	push_scissor(self.box, add_shape_box(self.box, core.style.rounding))
	push_stack(&core.container_stack, self) or_return

	layout_pos := self.box.lo - linalg.floor(self.scroll)
	layout_size := linalg.max(self.size, info.size)
	begin_layout({box = Box{layout_pos, layout_pos + layout_size}, isolated = true}) or_return
	self.layout = current_layout().?
	self.layout.next_cut_side = .Top

	return true
}

end_container :: proc() {
	self := current_container().?
	layout := current_layout().?
	self.size = linalg.max(layout.content_size + layout.spacing_size, self.size)

	// Clamp scroll
	self.desired_scroll = linalg.max(
		linalg.min(self.desired_scroll, self.size - (self.box.hi - self.box.lo)),
		0,
	)
	delta_scroll := (self.desired_scroll - self.scroll) * core.delta_time * 15
	self.scroll += delta_scroll

	self.scroll_x = self.size.x > box_width(self.box) && !self.no_scroll_x
	self.scroll_y = self.size.y > box_height(self.box) && !self.no_scroll_y

	self.scroll_time.x = animate(self.scroll_time.x, 0.2, self.scroll_x)
	self.scroll_time.y = animate(self.scroll_time.y, 0.2, self.scroll_y)

	if abs(delta_scroll.x) > 0.1 || abs(delta_scroll.y) > 0.1 {
		core.draw_next_frame = true
	}

	end_layout()

	inner_box := shrink_box(self.box, 4)

	if self.scroll_y {
		box := get_box_cut_right(
			inner_box,
			self.scroll_time.y * core.style.shape.scrollbar_thickness,
		)
		if self.scroll_x {
			box.hi.y -= self.scroll_time.x * core.style.shape.scrollbar_thickness
		}
		if scrollbar({make_visible = self.active || abs(delta_scroll.y) > 0.1, vertical = true, box = box, pos = &self.scroll.y, travel = self.size.y - box_height(self.box), handle_size = box_height(box) * box_height(self.box) / self.size.y}).self.state >=
		   {.Pressed} {
			self.desired_scroll.y = self.scroll.y
		}
	}
	if self.scroll_x {
		box := get_box_cut_bottom(
			inner_box,
			self.scroll_time.x * core.style.shape.scrollbar_thickness,
		)
		if self.scroll_y {
			box.hi.x -= self.scroll_time.y * core.style.shape.scrollbar_thickness
		}
		if scrollbar({make_visible = self.active || abs(delta_scroll.x) > 0.1, box = box, pos = &self.scroll.x, travel = self.size.x - box_width(self.box), handle_size = box_width(box) * box_width(self.box) / self.size.x}).self.state >=
		   {.Pressed} {
			self.desired_scroll.x = self.scroll.x
		}
	}

	// Table outline
	draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.style.color.substance)

	pop_scissor()
	pop_stack(&core.container_stack)
}

current_container :: proc() -> Maybe(^Container) {
	if core.container_stack.height > 0 {
		return core.container_stack.items[core.container_stack.height - 1]
	}
	return nil
}

Scissor :: struct {
	box: Box,
	shape: u32,
}

push_scissor :: proc(box: Box, shape: u32 = 0) {
	box := box
	if scissor, ok := current_scissor().?; ok {
		box = clamp_box(box, scissor.box)
	}
	push_stack(&core.scissor_stack, Scissor{box = box, shape = shape})
	set_scissor_shape(shape)
}

pop_scissor :: proc() {
	pop_stack(&core.scissor_stack)
	if scissor, ok := current_scissor().?; ok {
		set_scissor_shape(scissor.shape)
	}
}

current_scissor :: proc() -> Maybe(Scissor) {
	if core.scissor_stack.height > 0 {
	return core.scissor_stack.items[core.scissor_stack.height - 1]
	}
	return nil
}

@(deferred_out = __container)
container :: proc(info: Container_Info, loc := #caller_location) -> bool {
	return begin_container(info, loc)
}

@(private)
__container :: proc(ok: bool) {
	if ok {
		end_container()
	}
}
