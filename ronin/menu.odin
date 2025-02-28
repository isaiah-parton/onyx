package ronin

import kn "local:katana"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

solve_menu_content_height :: proc(how_many_items, how_many_dividers: int) -> f32 {
	style := get_current_style()
	return style.menu_padding * 2 * f32(how_many_dividers) + f32(how_many_items) * style.scale + f32(how_many_dividers)
}

solve_menu_box :: proc(anchor_box: Box, size: [2]f32, margin: f32, side: Side, align: f32) -> (box: Box) {
	if int(side) > 1 {
		box.lo.x = math.lerp(anchor_box.lo.x, anchor_box.hi.x - size.x, align)
		box.hi.x = box.lo.x + size.x
	} else {
		box.lo.y = math.lerp(anchor_box.lo.y, anchor_box.hi.y - size.y, align)
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
	text_layout := kn.make_text(text, get_current_style().default_text_size, get_current_style().default_font)
	object.size = text_layout.size + global_state.style.text_padding * {1, 2}
	object.size.x += object.size.y
	if begin_object(object) {

		object.animation.hover = animate(object.animation.hover, 0.1, .Hovered in object.state.current)
		object.animation.press = animate(object.animation.press, 0.08, .Pressed in object.state.current)

		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		if object_is_visible(object) {
			text_color: kn.Color = get_current_style().color.content
			rounding := get_current_options().radius

			color := get_current_style().color.button
			kn.add_box_lines(object.box, 1, rounding, paint = color)
			kn.add_box(
				object.box,
				rounding,
				paint = kn.fade(color, math.lerp(math.lerp(f32(0.5), f32(0.8), object.animation.hover), f32(1.0), object.animation.press)),
			)
			kn.add_text(
				text_layout,
				{
					object.box.lo.x + get_current_style().text_padding.x,
					box_center_y(object.box),
				} - text_layout.size * {0, 0.5},
				paint = text_color,
			)
			box := shrink_box(get_box_cut_right(object.box, box_height(object.box)), 8)
			kn.add_box({box.lo, {box.hi.x, box.lo.y + 1}}, paint = text_color)
			kn.add_box({{box.lo.x, box_center_y(box)}, {box.hi.x, box_center_y(box) + 1}}, paint = text_color)
			kn.add_box({{box.lo.x, box.hi.y}, {box.hi.x, box.hi.y + 1}}, paint = text_color)
		}
		end_object()
	}
	return begin_menu_with_activator(object, width, how_many_items, how_many_dividers)
}

begin_submenu :: proc(label: string, width: f32, how_many_items, how_many_dividers: int, loc := #caller_location) -> bool {
	object := get_object(hash(loc))
	style := get_current_style()
	label_text := kn.make_text(label, style.default_text_size, style.default_font)
	object.size = label_text.size + global_state.style.text_padding * 2
	if begin_object(object) {

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}

		object.animation.hover = animate(object.animation.hover, 0.1, .Hovered in object.state.current)
		object.animation.press = animate(object.animation.press, 0.08, .Pressed in object.state.current)

		if object_is_visible(object) {
			text_color: kn.Color = style.color.content
			rounding := get_current_options().radius

			color := style.color.button
			kn.add_box(
				object.box,
				rounding,
				paint = kn.fade(
					style.color.button,
					max((object.animation.hover + object.animation.press) * 0.5, f32(i32(.Focused in object.state.current))) *
					0.75,
				),
			)
			kn.add_text(
				label_text,
				{
					object.box.lo.x + style.text_padding.x,
					box_center_y(object.box),
				} - label_text.size * {0, 0.5},
				paint = text_color,
			)
			kn.add_arrow(box_center(get_box_cut_right(object.box, box_height(object.box))), 5, 1, paint = style.color.content)
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
		get_current_style().menu_padding * 2
	box :=
		solve_menu_box(activator.box, size, get_current_style().popup_margin, side, 0)
	if int(side) < 2 {
		box = move_box(box, {0, -get_current_style().menu_padding})
	}

	push_id(activator.id)

	push_stack(&global_state.object_stack, activator)

	begin_layer(.Back)

	set_next_box(box)
	begin_layout(as_column) or_return

	begin_group() or_return

	foreground()
	set_width(to_layout_width)
	set_height(that_of_object)
	shrink(get_current_style().menu_padding)

	new_options := get_current_options()^
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
		if object, ok := get_current_object(); ok {
			object.state.next += group.current_state & {.Focused, .Open}
			object.state.current += group.current_state & {.Focused, .Open}
			if .Focused in (object.state.previous - object.state.current) {
				object.state.current -= {.Open}
			}
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
	layout := get_current_layout()
	cut_box(&layout.box, layout.side, get_current_style().menu_padding)
	line_box := cut_box(&layout.box, layout.side, 1)
	i := int(layout.side) / 2
	j := 1 - i
	line_box.lo[j] = layout.bounds.lo[j]
	line_box.hi[j] = layout.bounds.hi[j]
	kn.add_box(line_box, paint = get_current_style().color.lines)
	cut_box(&layout.box, layout.side, get_current_style().menu_padding)
}
