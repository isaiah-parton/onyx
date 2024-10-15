package onyx

import "base:intrinsics"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:reflect"

Breadcrumb_Info :: struct {
	using _:   Widget_Info,
	text:      string,
	index:     ^int,
	options:   []string,
	is_tail:   bool,
	has_menu:  bool,
	text_info: Text_Info,
}

init_breadcrumb :: proc(using info: ^Breadcrumb_Info, loc := #caller_location) -> bool {
	assert(info != nil)
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	has_menu = len(options) > 1 && index != nil
	text_info = {
		text = options[index^] if has_menu else text,
		font = core.style.default_font,
		size = core.style.button_text_size,
	}
	desired_size = measure_text(text_info)
	if !is_tail {
		desired_size.x += 20
	}
	if has_menu {
		desired_size.x += 15
	}
	fixed_size = true
	return true
}

add_breadcrumb :: proc(using info: ^Breadcrumb_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	if info.index == nil {
		return false
	}

	kind := widget_kind(self, Menu_Widget_Kind)
	menu_behavior(self)

	if self.visible {
		color := fade(core.style.color.content, 0.5 + 0.5 * self.hover_time)
		draw_text(self.box.lo, info.text_info, color)
		if info.has_menu {
			draw_arrow({math.floor(self.box.hi.x - 24), box_center_y(self.box)}, 5, color)
		}
		if !info.is_tail {
			origin: [2]f32 = {math.floor(self.box.hi.x - 10), box_center_y(self.box)}
			begin_path()
			point(origin + {-2, 6})
			point(origin + {2, -6})
			stroke_path(2, fade(core.style.color.content, 0.5))
			end_path()
		}
	}

	if info.has_menu {
		if .Pressed in self.state {
			self.state += {.Open}
		}

		if .Open in self.state {

			MAX_OPTIONS :: 30
			menu_size: [2]f32
			buttons: [MAX_OPTIONS]Button_Info

			// First define the buttons and calculate desired menu size
			for option, o in info.options[:min(len(info.options), MAX_OPTIONS)] {
				if o == info.index^ do continue
				push_id(o)
				buttons[o] = {
					text      = option,
					style     = .Ghost,
					font_size = 20,
				}
				init_button(&buttons[0]) or_continue
				menu_size.x = max(menu_size.x, buttons[o].desired_size.x)
				menu_size.y += buttons[o].desired_size.y
				pop_id()
			}

			// Add some extra space
			menu_size += 10

			// Find horizontal center
			center_x := box_center_x(self.box) - 10

			// Define the menu box
			box: Box = {
				{center_x - menu_size.x / 2, self.box.hi.y + core.style.shape.menu_padding},
				{
					center_x + menu_size.x / 2,
					self.box.hi.y + core.style.shape.menu_padding + menu_size.y,
				},
			}

			open_time := ease.quadratic_out(kind.open_time)
			layer_scale: f32 = 0.7 + 0.3 * open_time
			// Begin the menu layer
			layer_info := Layer_Info {
				id      = self.id,
				box     = box,
				origin  = {box_center_x(box), box.lo.y},
				scale   = ([2]f32)(layer_scale),
				parent  = current_layer().?,
				opacity = open_time,
			}
			if begin_layer(&layer_info) {
				defer end_layer()
				if .Focused in layer_info.self.state {
					self.next_state += {.Focused}
				}
				foreground()
				shrink(5)
				set_side(.Top)
				set_width_fill()
				for &button, b in buttons[:len(info.options)] {
					if b == info.index^ do continue
					if add_button(&button) && button.clicked {
						index^ = b
						self.state -= {.Open}
					}
				}
				if .Hovered not_in layer_info.self.state && .Focused not_in self.state {
					self.state -= {.Open}
				}
			}

		}
	}
	return true
}

breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Info {
	info := info
	if init_breadcrumb(&info, loc) {
		add_breadcrumb(&info)
	}
	return info
}
