package onyx

import "base:intrinsics"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:reflect"

Breadcrumb_Info :: struct {
	using _:     Widget_Info,
	index:       int,
	options:     []string,
	is_tail:     bool,
	__has_menu:  bool,
	__text_info: Text_Info,
}

Breadcrumb_Result :: struct {
	using _: Widget_Result,
	index:   Maybe(int),
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
	widget, ok := begin_widget(info)
	if !ok do return

	result.self = widget
	kind := widget_kind(widget, Menu_Widget_Kind)
	menu_behavior(widget)

	if widget.visible {
		color := fade(core.style.color.content, 0.5 + 0.5 * widget.hover_time)
		draw_text(widget.box.lo, info.__text_info, color)
		if info.__has_menu {
			draw_arrow({math.floor(widget.box.hi.x - 24), box_center_y(widget.box)}, 5, color)
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
				buttons[o] = make_button({text = option, kind = .Ghost, font_size = 20})
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
				{center_x - menu_size.x / 2, widget.box.hi.y + core.style.shape.menu_padding},
				{
					center_x + menu_size.x / 2,
					widget.box.hi.y + core.style.shape.menu_padding + menu_size.y,
				},
			}

			open_time := ease.quadratic_out(kind.open_time)
			layer_scale: f32 = 0.7 + 0.3 * open_time
			// Begin the menu layer
			begin_layer(
				{
					id = widget.id,
					box = box,
					origin = {box_center_x(box), box.lo.y},
					scale = ([2]f32)(layer_scale),
					parent = current_layer().?,
					opacity = open_time,
				},
			)
			layer := current_layer().?
			if .Focused in layer.state {
				widget.next_state += {.Focused}
			}
			foreground()
			shrink(5)
			set_side(.Top)
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


	end_widget()
	return
}

do_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Result {
	return add_breadcrumb(make_breadcrumb(info, loc))
}
