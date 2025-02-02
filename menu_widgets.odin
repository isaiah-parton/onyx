package onyx

import "../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

solve_menu_content_height :: proc(how_many_items, how_many_dividers: int) -> f32 {
	style := style()
	return style.menu_padding * 2 * f32(how_many_dividers) + f32(how_many_items) * style.visual_size.y + f32(how_many_dividers)
}

solve_menu_box :: proc(anchor_box: Box, size: [2]f32, margin: f32, side: Side, align: Align) -> (box: Box) {
	if int(side) > 1 {
		switch align {
		case .Near:
			box.lo.x = anchor_box.lo.x
		case .Center:
			box.lo.x = box_center_x(anchor_box) - size.x / 2
		case .Far:
			box.lo.x = anchor_box.hi.x - size.x
		}
		box.hi.x = box.lo.x + size.x
	} else {
		switch align {
		case .Near:
			box.lo.y = anchor_box.lo.y
		case .Center:
			box.lo.y = box_center_y(anchor_box) - size.y / 2
		case .Far:
			box.lo.y = anchor_box.hi.y - size.y
		}
		box.hi.y = box.lo.y + size.y
	}
	switch side {
	case .Bottom:
		box.lo.y = anchor_box.hi.y + margin
		box.hi.y = box.lo.y + size.y
	case .Top:
		box.hi.y = anchor_box.lo.y - margin
		box.lo.y = box.hi.y - size.y
	case .Left:
		box.hi.x = anchor_box.lo.x - margin
		box.lo.x = box.hi.x - size.x
	case .Right:
		box.lo.x = anchor_box.hi.x + margin
		box.hi.x = box.lo.x + size.x
	}
	return
}

begin_menu :: proc(text: string, width: f32, how_many_items, how_many_dividers: int, loc := #caller_location) -> bool {
	object := get_object(hash(loc))
	text_layout := vgo.make_text_layout(text, style().default_text_size, style().default_font)
	object.size = text_layout.size + global_state.style.text_padding * {1, 2}
	object.size.x += object.size.y
	if begin_object(object) {
		object.box = next_box(object.size)

		object.hover_time = animate(object.hover_time, 0.1, .Hovered in object.state.current)
		object.press_time = animate(object.press_time, 0.08, .Pressed in object.state.current)

		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		if object_is_visible(object) {
			text_color: vgo.Color = style().color.content
			rounding := current_options().radius

			color := style().color.button
			vgo.stroke_box(object.box, 1, rounding, paint = color)
			vgo.fill_box(
				object.box,
				rounding,
				paint = vgo.fade(color, math.lerp(math.lerp(f32(0.5), f32(0.8), object.hover_time), f32(1.0), object.press_time)),
			)
			vgo.fill_text_layout(
				text_layout,
				{
					object.box.lo.x + global_state.style.text_padding.x,
					box_center_y(object.box),
				},
				align = {0, 0.5},
				paint = text_color,
			)
			box := shrink_box(get_box_cut_right(object.box, box_height(object.box)), 8)
			vgo.fill_box({box.lo, {box.hi.x, box.lo.y + 1}}, paint = text_color)
			vgo.fill_box({{box.lo.x, box_center_y(box)}, {box.hi.x, box_center_y(box) + 1}}, paint = text_color)
			vgo.fill_box({{box.lo.x, box.hi.y}, {box.hi.x, box.hi.y + 1}}, paint = text_color)
		}
		end_object()
	}
	return begin_menu_with_activator(object, width, how_many_items, how_many_dividers)
}

begin_submenu :: proc(text: string, width: f32, how_many_items, how_many_dividers: int, loc := #caller_location) -> bool {
	object := get_object(hash(loc))
	text_layout := vgo.make_text_layout(text, style().default_text_size, style().default_font)
	object.size = text_layout.size + global_state.style.text_padding * 2
	if begin_object(object) {
		object.box = next_box(object.size)

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}

		object.hover_time = animate(object.hover_time, 0.1, .Hovered in object.state.current)
		object.press_time = animate(object.press_time, 0.08, .Pressed in object.state.current)

		if object_is_visible(object) {
			text_color: vgo.Color = style().color.content
			rounding := current_options().radius

			color := style().color.button
			vgo.fill_box(
				object.box,
				rounding,
				paint = vgo.fade(
					style().color.button,
					max((object.hover_time + object.press_time) * 0.5, f32(i32(.Focused in object.state.current))) *
					0.75,
				),
			)
			vgo.fill_text_layout(
				text_layout,
				{
					object.box.lo.x + global_state.style.text_padding.x,
					box_center_y(object.box),
				},
				align = {0, 0.5},
				paint = text_color,
			)
			vgo.arrow(box_center(get_box_cut_right(object.box, box_height(object.box))), 5, 1, paint = style().color.content)
		}
		end_object()
	}
	return begin_menu_with_activator(object, width, how_many_items, how_many_dividers, side = .Right)
}

begin_menu_with_activator :: proc(
	activator: ^Object,
	width: f32,
	how_many_items, how_many_dividers: int,
	side: Side = .Bottom,
) -> bool {
	if activator == nil {
		return false
	}
	if .Focused in (activator.state.current + activator.state.previous) {
		activator.state.current += {.Open}
	}
	if .Open not_in (activator.state.current) {
		return false
	}
	size :=
		[2]f32{max(width, box_width(activator.box)), solve_menu_content_height(how_many_items, how_many_dividers)} +
		style().menu_padding * 2
	box :=
		solve_menu_box(activator.box, size, style().popup_margin, side, .Near)
	if int(side) < 2 {
		box = move_box(box, {0, -style().menu_padding})
	}

	push_id(activator.id)

	push_stack(&global_state.object_stack, activator)

	begin_layer(kind = .Background)

	set_next_box(box)
	begin_layout(.Top) or_return

	begin_group() or_return

	foreground()
	set_width(remaining_space().x)
	set_height(0)
	shrink(style().menu_padding)

	new_options := current_options()^
	if global_state.mouse_release_time._nsec < activator.click.press_time._nsec {
		new_options.hover_to_focus = true
		global_state.dragged_object = 0
	}
	push_options(new_options)

	return true
}

end_menu :: proc() {
	pop_options()
	if group, ok := end_group(); ok {
		object := current_object().?
		object.state.next += group.current_state & {.Focused, .Open}
		object.state.current += group.current_state & {.Focused, .Open}
		if .Focused in (object.state.previous - object.state.current) {
			object.state.current -= {.Open}
		}
	}
	end_layout()
	end_layer()
	pop_stack(&global_state.object_stack)
	pop_id()
}

menu_button :: proc(text: string, loc := #caller_location) -> Button_Result {
	return button(text, accent = .Subtle, loc = loc)
}

menu_divider :: proc() {
	layout := current_layout().?
	side := current_options().side
	cut_box(&layout.box, side, style().menu_padding)
	line_box := cut_box(&layout.box, side, 1)
	i := int(side) / 2
	j := 1 - i
	line_box.lo[j] = layout.bounds.lo[j]
	line_box.hi[j] = layout.bounds.hi[j]
	vgo.fill_box(line_box, paint = style().color.foreground_stroke)
	cut_box(&layout.box, side, style().menu_padding)
}
