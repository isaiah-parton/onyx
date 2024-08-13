package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

import "base:intrinsics"

Bar_Graph :: struct {
	stacked,
	show_labels,
	show_tooltip,
	horizontal: bool,
}

Line_Graph :: struct {
	show_dots,
	filled: bool,
}

Graph_Kind :: union #no_nil {
	Bar_Graph,
	Line_Graph,
}

Graph_Entry :: struct($T: typeid) {
	label: string,
	values: []T,
}

Graph_Field_Info :: struct {
	name: string,
	color: Color,
}

Graph_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _: Generic_Widget_Info,

	lo, hi, increment: T,
	kind: Graph_Kind,

	spacing: f32,

	fields: []Graph_Field_Info,
	entries: []Graph_Entry(T),
}

Widget_Variant_Graph :: struct{
	dot_times: [dynamic]f32,
	bar_time: f32,
}

make_graph :: proc(info: Graph_Info($T), loc := #caller_location) -> Graph_Info(T) {
	info := info
	info.id = hash(loc)
	info.spacing = max(info.spacing, 10)
	info.desired_size = {
		info.spacing * f32(len(info.entries)),
		f32(info.hi - info.lo) * 2,
	}
	return info
}

add_graph :: proc(info: Graph_Info($T), loc := #caller_location) {
	widget := get_widget(info)

	widget.box = next_widget_box(info)
	variant := widget_variant(widget, Widget_Variant_Graph)
	variant.dot_times.allocator = widget.allocator

	box := widget.box

	widget.hover_time = animate(widget.hover_time, 0.2, .Hovered in widget.state)

	if len(info.entries) == 0 {
		return
	}

	switch kind in info.kind {

		case Line_Graph:
		if widget.visible {
			for v := info.lo; v <= info.hi; v += info.increment {
				p := math.floor(box.hi.y + (box.lo.y - box.hi.y) * (f32(v) / f32(info.hi - info.lo)))
				draw_box_fill({{box.lo.x, p}, {box.hi.x, p + 1}}, fade(core.style.color.substance, 0.5))
			}
			resize(&variant.dot_times, len(info.entries))

			hn := int(math.round((core.mouse_pos.x - box.lo.x) / ((box.hi.x -  box.lo.x) / f32(len(info.entries) - 1))))
			if hn >= 0 && hn < len(info.entries) {
				p := box.lo.x + (f32(hn) / f32(len(info.entries) - 1)) * (box.hi.x - box.lo.x)
				draw_line({p, box.lo.y}, {p, box.hi.y}, 2, fade(core.style.color.content, widget.hover_time * 0.5))
			}

			for &field, f in info.fields {
				lp: [2]f32
				begin_path()
				for &entry, e in info.entries {
					p: [2]f32 = {
						box.lo.x + (f32(e) / f32(len(info.entries) - 1)) * (box.hi.x - box.lo.x), 
						box.hi.y + (f32(entry.values[f] - info.lo) / f32(info.hi - info.lo)) * (box.lo.y - box.hi.y),
					}
					point(p)
				}
				stroke_path(2.5, field.color)
				end_path()
			}

			for &field, f in info.fields {
				lp: [2]f32
				for &entry, e in info.entries {
					point_time: f32 = f32(e) / f32(len(info.entries) - 1)
					p: [2]f32 = {
						box.lo.x + point_time * (box.hi.x - box.lo.x), 
						box.hi.y + (f32(entry.values[f] - info.lo) / f32(info.hi - info.lo)) * (box.lo.y - box.hi.y),
					}
					dot_time := variant.dot_times[e]
					dot_time = animate(dot_time, 0.1, hn == e && .Hovered in widget.state)
					if kind.show_dots {
						draw_arc_fill(p, 4.5, 0, math.TAU, field.color)
					}
					if dot_time > 0 {
						draw_arc_fill(p, 8 * dot_time, 0, math.TAU, field.color)
						draw_arc_fill(p, 6 * dot_time, 0, math.TAU, core.style.color.foreground)
					}
					variant.dot_times[e] = dot_time
					lp = p
				}
			}
		}

		case Bar_Graph:

		PADDING :: 5
		block_size: f32 = (box.hi.x - box.lo.x) / f32(len(info.entries))
		hovered_entry := clamp(int((core.mouse_pos.x - widget.box.lo.x) / block_size), 0, len(info.entries) - 1)

		if .Hovered in widget.state {
			draw_box_fill({{box.lo.x + f32(hovered_entry) * block_size, box.lo.y}, {box.lo.x + f32(hovered_entry) * block_size + block_size, box.hi.y}}, fade(core.style.color.substance, 0.5))
		}

		if kind.stacked {

			for v := info.lo; v <= info.hi; v += info.increment / T(len(info.fields)) {
				p := math.floor(box.hi.y + (box.lo.y - box.hi.y) * (f32(v) / f32(info.hi - info.lo)))
				draw_box_fill({{box.lo.x, p}, {box.hi.x, p + 1}}, fade(core.style.color.substance, 0.5))
			}

			for &entry, e in info.entries {

				offset: f32 = box.lo.x + block_size * f32(e)
				block: Box = {
					{offset + PADDING, box.lo.y},
					{offset + block_size - PADDING, box.hi.y},
				}

				if len(entry.label) > 0 {
					draw_text({(block.lo.x + block.hi.x) / 2, block.hi.y + 2}, {
						text = entry.label, 
						font = core.style.fonts[.Light],
						size = 16,
						align_h = .Middle,
						align_v = .Top,
					}, core.style.color.content)
				}

				height: f32 = 0

				#reverse for &field, f in info.fields {
					if entry.values[f] == 0 {
						continue
					}
					field_height := (f32(entry.values[f]) / f32(info.hi * len(info.fields))) * (box.hi.y - box.lo.y)
					corners: Corners
					if f == 0 {
						corners += {.Top_Left, .Top_Right}
					}
					if f == len(info.fields) - 1 {
						corners += {.Bottom_Left, .Bottom_Right}
					}
					draw_rounded_box_corners_fill({{block.lo.x, block.hi.y - (height + field_height)}, {block.hi.x, block.hi.y - height}}, core.style.rounding, corners, field.color)
					height += field_height
				}
			}
		} else {
			// Draw incremental lines
			for v := info.lo; v <= info.hi; v += info.increment {
				p := math.floor(box.hi.y + (box.lo.y - box.hi.y) * (f32(v) / f32(info.hi - info.lo)))
				draw_box_fill({{box.lo.x, p}, {box.hi.x, p + 1}}, fade(core.style.color.substance, 0.5))
			}
			for &entry, e in info.entries {
				block := cut_box_left(&box, block_size)
				if len(info.fields) > 1 {
					block.lo.x += PADDING
					block.hi.x -= PADDING
				}
				bar_size := (block.hi.x - block.lo.x) / f32(len(info.fields))
				if len(entry.label) > 0 {
					draw_text({(block.lo.x + block.hi.x) / 2, block.hi.y + 2}, {
						text = entry.label, 
						font = core.style.fonts[.Light],
						size = 16,
						align_h = .Middle,
						align_v = .Top,
					}, core.style.color.content)
				}
				for &field, f in info.fields {
					bar := cut_box_left(&block, bar_size)
					bar.lo.x += 1
					bar.hi.x -= 1
					bar.lo.y = bar.hi.y - (f32(entry.values[f]) / f32(info.hi)) * (bar.hi.y - bar.lo.y)
					draw_rounded_box_fill(bar, core.style.rounding, field.color)
					if kind.show_labels {
						draw_text({(bar.lo.x + bar.hi.x) / 2, bar.lo.y - 2}, {
							text = tmp_print(entry.values[f]), 
							font = core.style.fonts[.Light],
							size = 16,
							align_h = .Middle,
							align_v = .Bottom,
						}, fade(core.style.color.content, 0.5 if entry.values[f] == 0 else 1.0))
					}
				}
			}
		}
		if .Hovered in widget.state {
			// Tooltip
			begin_tooltip({
				bounds = widget.box,
				size = {150, f32(len(info.fields)) * 26 + 6},
				time = ease.cubic_in_out(widget.hover_time),
			})
				shrink(3)
				for &field, f in info.fields {
					tip_box := shrink_box(cut_box(&current_layout().box, .Top, 26), 3)
					draw_rounded_box_fill(cut_box_left(&tip_box, 6), core.style.rounding, field.color)
					draw_text({tip_box.lo.x + 8, (tip_box.lo.y + tip_box.hi.y) / 2}, {
						text = field.name, 
						font = core.style.fonts[.Regular], 
						size = 18,
						align_v = .Middle,
					}, color = core.style.color.content)
					draw_text({tip_box.hi.x - 4, (tip_box.lo.y + tip_box.hi.y) / 2}, {
						text = tmp_printf("%v", info.entries[hovered_entry].values[f]), 
						font = core.style.fonts[.Regular], 
						size = 18,
						align_h = .Right,
						align_v = .Middle,
					}, color = core.style.color.content)
				}
			end_tooltip()
		}
	}


	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))
}

do_graph :: proc(info: Graph_Info($T), loc := #caller_location) {
	add_graph(make_graph(info, loc))
}