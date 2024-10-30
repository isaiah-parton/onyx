package onyx

import "../../vgo"
import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

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

Graph_Entry :: struct {
	label:  string,
	values: []f64,
}

Graph_Field_Info :: struct {
	name:  string,
	color: vgo.Color,
}

Graph_Info :: struct {
	using _:           Widget_Info,
	lo, hi, increment: f64,
	kind:              Graph_Kind,
	spacing:           f32,
	format:            string,
	fields:            []Graph_Field_Info,
	entries:           []Graph_Entry,
	label_tooltip:     bool,
}

Graph_Widget_Kind :: struct {
	dot_times: [100]f32,
}

init_graph :: proc(using info: ^Graph_Info, loc := #caller_location) -> bool {
	if len(entries) == 0 do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	spacing = max(spacing, 10)
	desired_size = {spacing * f32(len(entries)), f32(hi - lo) * 2}
	return true
}

add_graph :: proc(using info: ^Graph_Info, loc := #caller_location) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	inner_box := self.box

	self.hover_time = animate(self.hover_time, 0.2, .Hovered in self.state)

	tooltip_idx: int
	tooltip_pos: Maybe([2]f32)
	variant := widget_kind(self, Graph_Widget_Kind)
	switch kind in kind {

	case Line_Graph:
		if self.visible {
			for v := lo; v <= hi; v += increment {
				p := math.floor(
					inner_box.hi.y + (inner_box.lo.y - inner_box.hi.y) * (f32(v) / f32(hi - lo)),
				)
				vgo.fill_box(
					{{inner_box.lo.x, p}, {inner_box.hi.x, p + 1}},
					paint = vgo.fade(core.style.color.substance, 0.5),
				)
			}

			spacing: f32 = (inner_box.hi.x - inner_box.lo.x) / f32(len(entries) - 1)
			hn := int(math.round((core.mouse_pos.x - inner_box.lo.x) / spacing))
			tooltip_idx = clamp(hn, 0, len(entries) - 1)
			tooltip_pos = [2]f32 {
				inner_box.lo.x +
				math.round((core.mouse_pos.x - inner_box.lo.x) / spacing) * spacing,
				core.mouse_pos.y,
			}

			for &field, f in fields {
				// begin_path()
				// for &entry, e in entries {
				// 	point(
				// 		{
				// 			inner_box.lo.x +
				// 			(f32(e) / f32(len(entries) - 1)) * (inner_box.hi.x - inner_box.lo.x),
				// 			inner_box.hi.y +
				// 			(f32(entry.values[f] - lo) / f32(hi - lo)) *
				// 				(inner_box.lo.y - inner_box.hi.y),
				// 		},
				// 	)
				// }
				// path := get_path()
				// for i in 0 ..< path.count - 1 {
				// 	// Points
				// 	p0 := path.points[max(i - 1, 0)]
				// 	p1 := path.points[i]
				// 	p2 := path.points[min(i + 1, path.count - 1)]
				// 	p3 := path.points[min(i + 2, path.count - 1)]
				// 	// Control points
				// 	c1 := p1 + (p2 - p0) / 6
				// 	c2 := p2 - (p3 - p1) / 6
				// 	draw_cubic_bezier(p1, c1, c2, p2, 2, field.color)
				// }
				// end_path()
			}

			if .Hovered in self.state && hn >= 0 && hn < len(entries) {
				p :=
					inner_box.lo.x +
					(f32(hn) / f32(len(entries) - 1)) * (inner_box.hi.x - inner_box.lo.x)
				vgo.fill_box(
					{{p, inner_box.lo.y}, {p + 1, inner_box.hi.y}},
					paint = core.style.color.content,
				)
			}

			for &field, f in fields {
				lp: [2]f32
				for &entry, e in entries {
					point_time: f32 = f32(e) / f32(len(entries) - 1)
					p: [2]f32 = {
						inner_box.lo.x + point_time * (inner_box.hi.x - inner_box.lo.x),
						inner_box.hi.y +
						(f32(entry.values[f] - lo) / f32(hi - lo)) *
							(inner_box.lo.y - inner_box.hi.y),
					}
					dot_time := variant.dot_times[e]
					dot_time = animate(dot_time, 0.15, hn == e && .Hovered in self.state)
					if kind.show_dots {
						vgo.fill_circle(p, 4.5, field.color)
					}
					if dot_time > 0 {
						vgo.fill_circle(p, 8 * dot_time, field.color)
						vgo.fill_circle(p, 6 * dot_time, core.style.color.foreground)
					}
					variant.dot_times[e] = dot_time
					lp = p
				}
			}
		}

	case Bar_Graph:
		PADDING :: 5
		block_size: f32 = (inner_box.hi.x - inner_box.lo.x) / f32(len(entries))
		tooltip_idx = clamp(
			int((core.mouse_pos.x - self.box.lo.x) / block_size),
			0,
			len(entries) - 1,
		)

		if .Hovered in self.state {
			vgo.fill_box(
				{
					{inner_box.lo.x + f32(tooltip_idx) * block_size, inner_box.lo.y},
					{inner_box.lo.x + f32(tooltip_idx) * block_size + block_size, inner_box.hi.y},
				},
				paint = vgo.fade(core.style.color.substance, 0.5),
			)
		}

		if kind.stacked {

			for v := lo; v <= hi; v += increment / f64(len(fields)) {
				p := math.floor(
					inner_box.hi.y + (inner_box.lo.y - inner_box.hi.y) * (f32(v) / f32(hi - lo)),
				)
				vgo.fill_box(
					{{inner_box.lo.x, p}, {inner_box.hi.x, p + 1}},
					paint = vgo.fade(core.style.color.substance, 0.5),
				)
			}

			for &entry, e in entries {

				offset: f32 = inner_box.lo.x + block_size * f32(e)
				block: Box = {
					{offset + PADDING, inner_box.lo.y},
					{offset + block_size - PADDING, inner_box.hi.y},
				}

				if kind.entry_labels && len(entry.label) > 0 {
					vgo.fill_text(
						entry.label,
						core.style.default_font,
						16,
						{(block.lo.x + block.hi.x) / 2, block.hi.y + 2},
						paint = core.style.color.content,
					)
				}

				height: f32 = 0

				#reverse for &field, f in fields {
					if entry.values[f] == 0 {
						continue
					}
					field_height :=
						(f32(entry.values[f]) / f32(hi * f64(len(fields)))) *
						(inner_box.hi.y - inner_box.lo.y)
					vgo.fill_box(
						{
							{block.lo.x, block.hi.y - (height + field_height)},
							{block.hi.x, block.hi.y - height},
						},
						core.style.rounding,
						paint = field.color,
					)
					height += field_height
				}
			}
		} else {
			// Draw incremental lines
			for v := lo; v <= hi; v += increment {
				p := math.floor(
					inner_box.hi.y + (inner_box.lo.y - inner_box.hi.y) * (f32(v) / f32(hi - lo)),
				)
				vgo.fill_box(
					{{inner_box.lo.x, p}, {inner_box.hi.x, p + 1}},
					paint = vgo.fade(core.style.color.substance, 0.5),
				)
			}

			// For each entry
			for &entry, e in entries {
				// Cut a box for this block
				block := cut_box_left(&inner_box, block_size)
				if len(fields) > 1 {
					block.lo.x += PADDING
					block.hi.x -= PADDING
				}
				bar_size := (block.hi.x - block.lo.x) / f32(len(fields))

				// Draw entry label if enabled
				if kind.entry_labels && len(entry.label) > 0 {
					vgo.fill_text_aligned(
						entry.label,
						core.style.default_font,
						18,
						{(block.lo.x + block.hi.x) / 2, block.hi.y + 2},
						.Center,
						.Top,
						paint = core.style.color.content,
					)
				}

				// Draw a bar for each field
				for &field, f in fields {
					bar := cut_box_left(&block, bar_size)
					// bar.lo.x += 1
					// bar.hi.x -= 1
					bar.lo.y = bar.hi.y - (f32(entry.values[f]) / f32(hi)) * (bar.hi.y - bar.lo.y)
					corners: Corners = {}
					if f == 0 do corners += {.Top_Left, .Bottom_Left}
					if f == len(fields) - 1 do corners += {.Top_Right, .Bottom_Right}
					vgo.fill_box(
						bar,
						{core.style.rounding, core.style.rounding, 0, 0},
						field.color,
					)
					if kind.value_labels {
						vgo.fill_text_aligned(
							fmt.tprint(entry.values[f]),
							core.style.default_font,
							18,
							{(bar.lo.x + bar.hi.x) / 2, bar.lo.y - 2},
							.Center,
							.Center,
							paint = vgo.fade(core.style.color.content, 0.5 if entry.values[f] == 0 else 1.0),
						)
					}
				}
			}
		}
	}

	if .Hovered in self.state {
		tooltip_size: [2]f32 = {150, f32(len(fields)) * 26 + 6}
		if label_tooltip {
			tooltip_size += 26
		}
		// Tooltip
		begin_tooltip({bounds = self.box, size = tooltip_size})
		shrink_layout(3)
		if label_tooltip {
			box := cut_current_layout(.Top, [2]f32{0, 26})
			vgo.fill_text_aligned(
				entries[tooltip_idx].label,
				core.style.default_font,
				18,
				box.lo + [2]f32{5, 13},
				.Center,
				.Top,
				paint = core.style.color.content,
			)
		}
		for &field, f in fields {
			tip_box := shrink_box(cut_box(&current_layout().?.box, .Top, 26), 3)
			blip_box := shrink_box(cut_box_left(&tip_box, box_height(tip_box)), 4)
			vgo.fill_box(blip_box, paint = field.color)
			vgo.fill_text_aligned(
				field.name,
				core.style.default_font,
				18,
				{tip_box.lo.x, (tip_box.lo.y + tip_box.hi.y) / 2},
				.Left,
				.Center,
				paint = vgo.fade(core.style.color.content, 0.5),
			)
			vgo.fill_text_aligned(
				fmt.tprintf("%v", entries[tooltip_idx].values[f]),
				core.style.default_font,
				18,
				{tip_box.hi.x, (tip_box.lo.y + tip_box.hi.y) / 2},
				.Right,
				.Center,
				paint = core.style.color.content,
			)
		}
		end_tooltip()
	}

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	return true
}

graph :: proc(info: Graph_Info, loc := #caller_location) -> Graph_Info {
	info := info
	init_graph(&info, loc)
	add_graph(&info)
	return info
}
