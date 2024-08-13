package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Breadcrumb_Info :: struct {
	using _: Generic_Widget_Info,
	index: int,
	options: []string,
	is_tail: bool,

	__has_menu: bool,
	__text_info: Text_Info,
}

Breadcrumb_Result :: struct {
	using _: Generic_Widget_Result,
	index: Maybe(int),
}

make_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Info {
	info := info
	info.id = hash(loc)

	info.__text_info = {
		text = info.options[info.index],
		font = core.style.fonts[.Medium],
		size = core.style.button_text_size,
	}
	info.__has_menu = len(info.options) > 1 

	info.desired_size = measure_text(info.__text_info)
	if !info.is_tail {
		info.desired_size.x += 20
	}
	if info.__has_menu {
		info.desired_size.x += 15
	}
	info.fixed_size = true
	return info
}

add_breadcrumb :: proc(info: Breadcrumb_Info) -> (result: Breadcrumb_Result) {
	widget := get_widget(info)
	widget.box = next_widget_box(info)
	result.self = widget

	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)

	if widget.visible {
		draw_text(widget.box.lo, info.__text_info, fade(core.style.color.content, 0.5 + 0.5 * widget.hover_time))
		if info.__has_menu {
			origin: [2]f32 = {math.floor(widget.box.hi.x - 24), box_center_y(widget.box)}
			begin_path()
				point(origin + {-4, -2})
				point(origin + {0, 2})
				point(origin + {4, -2})
				stroke_path(2, fade(core.style.color.content, 0.5))
			end_path()
		}
		if !info.is_tail {
			origin: [2]f32 = {math.floor(widget.box.hi.x - 10), box_center_y(widget.box)}
			begin_path()
				point(origin + {-2, 6})
				point(origin + {2, -6})
				stroke_path(2, fade(core.style.color.content, 0.5))
			end_path()
		}
	}

	if info.__has_menu {
		widget.focus_time = animate(widget.focus_time, 0.2, .Open in widget.state)

		if .Pressed in widget.state {
			widget.state += {.Open}
		}
		
		if .Open in widget.state {

			MAX_OPTIONS :: 30
			menu_size: [2]f32
			buttons: [MAX_OPTIONS]Button_Info

			// First define the buttons and calculate desired menu size
			for option, o in info.options[:min(len(info.options), MAX_OPTIONS)] {
				if o == info.index do continue
				push_id(o)
					buttons[o] = make_button({
						text = option,
						kind = .Ghost,
						font_size = 14,
					})
					menu_size.x = max(menu_size.x, buttons[o].desired_size.x)
					menu_size.y += buttons[o].desired_size.y
				pop_id()
			}

			// Add some extra space
			menu_size += 10

			// Find horizontal center
			center_x := box_center_x(widget.box) - 10

			// Define the menu box
			box: Box = {
				{center_x - menu_size.x / 2, widget.box.hi.y + 10},
				{center_x + menu_size.x / 2, widget.box.hi.y + 10 + menu_size.y},
			}

			// Begin the menu layer
			begin_layer({
				id = widget.id,
				box = box,
				origin = {box_center_x(box), box.lo.y},
				scale = ([2]f32)(ease.cubic_in_out(widget.focus_time)),
				parent = current_layer().id,
			})
				layer := current_layer()
				if .Focused in current_layer().state {
					widget.next_state += {.Focused}
				}
				foreground()
				shrink(5)
				side(.Top)
				set_width_fill()
				for &button, b in buttons[:len(info.options)] {
					if b == info.index do continue
					if was_clicked(add_button(button)) {
						result.index = b
						widget.state -= {.Open}
					}
				}
			end_layer()

			if .Hovered not_in layer.state && .Focused not_in widget.state {
				widget.state -= {.Open}
			}
		}
	}

	if .Hovered in widget.state {
		core.cursor_type = .POINTING_HAND
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Result {
	return add_breadcrumb(make_breadcrumb(info, loc))
}
