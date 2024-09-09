package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

import "base:intrinsics"

Bar_Graph :: struct {
	stacked, value_labels, entry_labels, show_tooltip, horizontal: bool,
}

Line_Graph :: struct {
	show_dots, filled: bool,
}

Graph_Kind :: union #no_nil {
	Bar_Graph,
	Line_Graph,
}

Graph_Entry :: struct($T: typeid) {
	label:  string,
	values: []T,
}

Graph_Field_Info :: struct {
	name:  string,
	color: Color,
}

Graph_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _:           Generic_Widget_Info,
	lo, hi, increment: T,
	kind:              Graph_Kind,
	spacing:           f32,
	fields:            []Graph_Field_Info,
	entries:           []Graph_Entry(T),
	label_tooltip:     bool,
}

Graph_Widget_Kind :: struct {
	dot_times: [dynamic]f32,
	bar_time:  f32,
	vertices:  [dynamic]Vertex,
}

make_graph :: proc(info: Graph_Info($T), loc := #caller_location) -> Graph_Info(T) {
	info := info
	info.id = hash(loc)
	info.spacing = max(info.spacing, 10)
	info.desired_size = {info.spacing * f32(len(info.entries)), f32(info.hi - info.lo) * 2}
	return info
}

add_graph :: proc(info: Graph_Info($T), loc := #caller_location) {
	widget, ok := begin_widget(info)
	if !ok do return

	if len(info.entries) == 0 {
		return
	}

	// Set up variant and allocators
	variant := widget_kind(widget, Graph_Widget_Kind)
	variant.dot_times.allocator = widget.allocator
	variant.vertices.allocator = widget.allocator

	box := widget.box

	widget.hover_time = animate(widget.hover_time, 0.2, .Hovered in widget.state)


	tooltip_idx: int
	tooltip_pos: Maybe([2]f32)

	switch kind in info.kind {

	case Line_Graph:
		if widget.visible {
			for v := info.lo; v <= info.hi; v += info.increment {
				p := math.floor(
					box.hi.y + (box.lo.y - box.hi.y) * (f32(v) / f32(info.hi - info.lo)),
				)
				draw_box_fill(
					{{box.lo.x, p}, {box.hi.x, p + 1}},
					fade(core.style.color.substance, 0.5),
				)
			}
			resize(&variant.dot_times, len(info.entries))

			spacing: f32 = (box.hi.x - box.lo.x) / f32(len(info.entries) - 1)
			hn := int(math.round((core.mouse_pos.x - box.lo.x) / spacing))
			tooltip_idx = clamp(hn, 0, len(info.entries) - 1)
			tooltip_pos = [2]f32 {
				box.lo.x + math.round((core.mouse_pos.x - box.lo.x) / spacing) * spacing,
				core.mouse_pos.y,
			}

			for &field, f in info.fields {
				begin_path()
				for &entry, e in info.entries {
					point(
						{
							box.lo.x +
							(f32(e) / f32(len(info.entries) - 1)) * (box.hi.x - box.lo.x),
							box.hi.y +
							(f32(entry.values[f] - info.lo) / f32(info.hi - info.lo)) *
								(box.lo.y - box.hi.y),
						},
					)
				}
				path := get_path()
				weights: matrix[4, 4]f32 = {1, 0, 0, 0, -3, 3, 0, 0, 3, -6, 3, 0, -1, 3, -3, 1}
				for i in 0 ..< path.count - 1 {
					// Points
					p0 := path.points[max(i - 1, 0)]
					p1 := path.points[i]
					p2 := path.points[min(i + 1, path.count - 1)]
					p3 := path.points[min(i + 2, path.count - 1)]

					// Control points
					c1 := p1 + (p2 - p0) / 6
					c2 := p2 - (p3 - p1) / 6

					// Do curve
					segments := int((p2.x - p1.x) / 5)
					step: f32 = 1.0 / f32(segments)
					lp: [2]f32
					ti, bi: u32
					for n in 0 ..= segments {
						t: f32 = f32(n) * step
						times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
						p: [2]f32 = {
							(times * weights * (matrix[4, 1]f32){p1.x, c1.x, c2.x, p2.x})[0][0],
							(times * weights * (matrix[4, 1]f32){p1.y, c1.y, c2.y, p2.y})[0][0],
						}
						set_vertex_uv({})
						set_vertex_color(fade(field.color, (box.hi.y - p.y) / box_height(box)))
						nti := add_vertex(p)
						set_vertex_color({})
						nbi := add_vertex({p.x, box.hi.y})
						if n > 0 {
							add_indices(ti, nti, bi, nti, nbi, bi)
							draw_line(lp, p, 2, field.color)
						}
						ti = nti
						bi = nbi
						lp = p
					}
				}
				end_path()
			}

			if .Hovered in widget.state && hn >= 0 && hn < len(info.entries) {
				p := box.lo.x + (f32(hn) / f32(len(info.entries) - 1)) * (box.hi.x - box.lo.x)
				draw_box_fill({{p, box.lo.y}, {p + 1, box.hi.y}}, core.style.color.content)
			}

			for &field, f in info.fields {
				lp: [2]f32
				for &entry, e in info.entries {
					point_time: f32 = f32(e) / f32(len(info.entries) - 1)
					p: [2]f32 = {
						box.lo.x + point_time * (box.hi.x - box.lo.x),
						box.hi.y +
						(f32(entry.values[f] - info.lo) / f32(info.hi - info.lo)) *
							(box.lo.y - box.hi.y),
					}
					dot_time := variant.dot_times[e]
					dot_time = animate(dot_time, 0.15, hn == e && .Hovered in widget.state)
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
		tooltip_idx = clamp(
			int((core.mouse_pos.x - widget.box.lo.x) / block_size),
			0,
			len(info.entries) - 1,
		)

		if .Hovered in widget.state {
			draw_box_fill(
				{
					{box.lo.x + f32(tooltip_idx) * block_size, box.lo.y},
					{box.lo.x + f32(tooltip_idx) * block_size + block_size, box.hi.y},
				},
				fade(core.style.color.substance, 0.5),
			)
		}

		if kind.stacked {

			for v := info.lo; v <= info.hi; v += info.increment / T(len(info.fields)) {
				p := math.floor(
					box.hi.y + (box.lo.y - box.hi.y) * (f32(v) / f32(info.hi - info.lo)),
				)
				draw_box_fill(
					{{box.lo.x, p}, {box.hi.x, p + 1}},
					fade(core.style.color.substance, 0.5),
				)
			}

			for &entry, e in info.entries {

				offset: f32 = box.lo.x + block_size * f32(e)
				block: Box = {
					{offset + PADDING, box.lo.y},
					{offset + block_size - PADDING, box.hi.y},
				}

				if kind.entry_labels && len(entry.label) > 0 {
					draw_text(
						{(block.lo.x + block.hi.x) / 2, block.hi.y + 2},
						{
							text = entry.label,
							font = core.style.fonts[.Light],
							size = 16,
							align_h = .Middle,
							align_v = .Top,
						},
						core.style.color.content,
					)
				}

				height: f32 = 0

				#reverse for &field, f in info.fields {
					if entry.values[f] == 0 {
						continue
					}
					field_height :=
						(f32(entry.values[f]) / f32(info.hi * len(info.fields))) *
						(box.hi.y - box.lo.y)
					corners: Corners
					if f == 0 {
						corners += {.Top_Left, .Top_Right}
					}
					if f == len(info.fields) - 1 {
						corners += {.Bottom_Left, .Bottom_Right}
					}
					draw_rounded_box_corners_fill(
						{
							{block.lo.x, block.hi.y - (height + field_height)},
							{block.hi.x, block.hi.y - height},
						},
						core.style.rounding,
						corners,
						field.color,
					)
					height += field_height
				}
			}
		} else {
			// Draw incremental lines
			for v := info.lo; v <= info.hi; v += info.increment {
				p := math.floor(
					box.hi.y + (box.lo.y - box.hi.y) * (f32(v) / f32(info.hi - info.lo)),
				)
				draw_box_fill(
					{{box.lo.x, p}, {box.hi.x, p + 1}},
					fade(core.style.color.substance, 0.5),
				)
			}

			// For each entry
			for &entry, e in info.entries {
				// Cut a box for this block
				block := cut_box_left(&box, block_size)
				if len(info.fields) > 1 {
					block.lo.x += PADDING
					block.hi.x -= PADDING
				}
				bar_size := (block.hi.x - block.lo.x) / f32(len(info.fields))

				// Draw entry label if enabled
				if kind.entry_labels && len(entry.label) > 0 {
					draw_text(
						{(block.lo.x + block.hi.x) / 2, block.hi.y + 2},
						{
							text = entry.label,
							font = core.style.fonts[.Regular],
							size = 18,
							align_h = .Middle,
							align_v = .Top,
						},
						core.style.color.content,
					)
				}

				// Draw a bar for each field
				for &field, f in info.fields {
					bar := cut_box_left(&block, bar_size)
					// bar.lo.x += 1
					// bar.hi.x -= 1
					bar.lo.y =
						bar.hi.y - (f32(entry.values[f]) / f32(info.hi)) * (bar.hi.y - bar.lo.y)
					corners: Corners = {}
					if f == 0 do corners += {.Top_Left, .Bottom_Left}
					if f == len(info.fields) - 1 do corners += {.Top_Right, .Bottom_Right}
					draw_rounded_box_corners_fill(bar, core.style.rounding, corners, field.color)
					if kind.value_labels {
						draw_text(
							{(bar.lo.x + bar.hi.x) / 2, bar.lo.y - 2},
							{
								text = tmp_print(entry.values[f]),
								font = core.style.fonts[.Regular],
								size = 18,
								align_h = .Middle,
								align_v = .Bottom,
							},
							fade(core.style.color.content, 0.5 if entry.values[f] == 0 else 1.0),
						)
					}
				}
			}
		}
	}

	if .Hovered in widget.state {
		tooltip_size: [2]f32 = {150, f32(len(info.fields)) * 26 + 6}
		if info.label_tooltip {
			tooltip_size += 26
		}
		// Tooltip
		begin_tooltip(
			{
				pos = tooltip_pos,
				bounds = widget.box,
				size = tooltip_size,
				time = ease.cubic_in_out(widget.hover_time),
			},
		)
		shrink(3)
		if info.label_tooltip {
			box := cut_current_layout(.Top, [2]f32{0, 26})
			draw_text(
				box.lo + [2]f32{5, 13},
				{
					text = info.entries[tooltip_idx].label,
					font = core.style.fonts[.Medium],
					size = 18,
					align_v = .Middle,
				},
				core.style.color.content,
			)
		}
		for &field, f in info.fields {
			tip_box := shrink_box(cut_box(&current_layout().?.box, .Top, 26), 3)
			blip_box := shrink_box(cut_box_left(&tip_box, box_height(tip_box)), 4)
			draw_box_fill(blip_box, field.color)
			draw_text(
				{tip_box.lo.x, (tip_box.lo.y + tip_box.hi.y) / 2},
				{
					text = field.name,
					font = core.style.fonts[.Medium],
					size = 18,
					align_v = .Middle,
				},
				color = fade(core.style.color.content, 0.5),
			)
			draw_text(
				{tip_box.hi.x, (tip_box.lo.y + tip_box.hi.y) / 2},
				{
					text = tmp_printf("%v", info.entries[tooltip_idx].values[f]),
					font = core.style.fonts[.Regular],
					size = 18,
					align_h = .Right,
					align_v = .Middle,
				},
				color = core.style.color.content,
			)
		}
		end_tooltip()
	}

	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}

	end_widget()
	return
}

do_graph :: proc(info: Graph_Info($T), loc := #caller_location) {
	add_graph(make_graph(info, loc))
}
