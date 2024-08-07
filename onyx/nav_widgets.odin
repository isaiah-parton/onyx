package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Breadcrumb_Info :: struct {
	using _: Generic_Widget_Info,
	text: string,
	is_tail: bool,
	options: []string,
}

Breadcrumb_Result :: struct {
	using _: Generic_Widget_Result,
}

make_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Info {
	info := info
	info.id = hash(loc)
	text_options := Text_Options{
		font = core.style.fonts[.Regular],
		size = core.style.button_text_size,
	}
	text_size := measure_text({
		text = info.text,
		options = text_options,
	})
	info.desired_size = text_size
	if !info.is_tail {
		info.desired_size.x += 20
	}
	if len(info.options) > 0 {
		info.desired_size.x += 20
	}
	info.fixed_size = true
	return info
}

display_breadcrumb :: proc(info: Breadcrumb_Info) -> (result: Breadcrumb_Result) {
	widget := get_widget(info)
	widget.box = next_widget_box(info)
	context.allocator = widget.allocator
	result.self = widget

	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)

	if widget.visible {
		draw_text(widget.box.lo, {
			text = info.text,
			options = Text_Options{
				font = core.style.fonts[.Regular],
				size = core.style.button_text_size,
			},
		}, fade(core.style.color.content, 0.5 + 0.5 * widget.hover_time))
		if len(info.options) > 0 {
			origin: [2]f32 = {math.floor(widget.box.hi.x - 30), box_center_y(widget.box)}
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
				// Slash
				point(origin + {-2, 6})
				point(origin + {2, -6})
				stroke_path(2, fade(core.style.color.content, 0.5))
			end_path()
		}
	}

	if .Focused in widget.state {
		begin_layer({
			box = attach_box_bottom(widget.box, 100),
		})
			foreground()
		end_layer()
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Result {
	return display_breadcrumb(make_breadcrumb(info, loc))
}
