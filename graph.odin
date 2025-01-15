package onyx

import "../vgo"
import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

Graph :: struct {
	low: f32,
	high: f32,
}

begin_graph :: proc(grid_size: [2]f32, low, high: f32, loc := #caller_location) -> bool {
	object := persistent_object(hash(loc))
	begin_object(object) or_return

	object.box = next_box({})
	object.variant = Graph{
		low = low,
		high = high,
	}

	push_clip(object.box)
	vgo.push_scissor(vgo.make_box(object.box, global_state.style.rounding))

	vgo.fill_box(object.box, paint = colors().field)
	if grid_size.y > 1 {
		for y: f32 = object.box.lo.y; y < object.box.hi.y; y += grid_size.y {
			vgo.line({object.box.lo.x, math.floor(y) + 0.5}, {object.box.hi.x, math.floor(y) + 0.5}, 1, colors().foreground)
		}
	}
	if grid_size.x > 1 {
		for x: f32 = object.box.lo.x; x < object.box.hi.x; x += grid_size.x {
			vgo.line({math.floor(x) + 0.5, object.box.lo.y}, {math.floor(x) + 0.5, object.box.hi.y}, 1, colors().foreground)
		}
	}

	return true
}

end_graph :: proc() {
	vgo.pop_scissor()
	pop_clip()
	end_object()
}

curve_graph :: proc(data: []f32, color: vgo.Color, format: string = "%v") -> bool {
	object := current_object().?

	graph := &object.variant.(Graph)
	inner_box := object.box

	if object_is_visible(object) {
		spacing: f32 = (inner_box.hi.x - inner_box.lo.x) / f32(len(data) - 1)
		hn := int(math.round((global_state.mouse_pos.x - inner_box.lo.x) / spacing))
		// tooltip_idx = clamp(hn, 0, len(data) - 1)
		// tooltip_pos = [2]f32 {
		// 	inner_box.lo.x +
		// 	math.round((global_state.mouse_pos.x - inner_box.lo.x) / spacing) * spacing,
		// 	global_state.mouse_pos.y,
		// }

		points := make([dynamic][2]f32, allocator = context.temp_allocator)
		for value, i in data {
			append(
				&points,
				[2]f32 {
					inner_box.lo.x +
					(f32(i) / f32(len(data) - 1)) * (inner_box.hi.x - inner_box.lo.x),
					inner_box.hi.y +
					(f32(value - graph.low) / f32(graph.high - graph.low)) * (inner_box.lo.y - inner_box.hi.y),
				},
			)
		}

		paint := vgo.make_linear_gradient(
			inner_box.lo,
			{inner_box.lo.x, inner_box.hi.y},
			vgo.fade(color, 1.0),
			vgo.fade(color, 0.0),
		)

		for i in 0 ..< len(points) {
			p0 := points[max(i - 1, 0)]
			p1 := points[i]
			p2 := points[min(i + 1, len(points) - 1)]
			p3 := points[min(i + 2, len(points) - 1)]
			c1 := p1 + (p2 - p0) / 6
			c2 := p2 - (p3 - p1) / 6
			a := p1
			b := c1
			c := c2
			d := p2
			ab := linalg.lerp(a, b, 0.5)
			cd := linalg.lerp(c, d, 0.5)
			mp := linalg.lerp(ab, cd, 0.5)
			shape0 := vgo.Shape{
				kind = .Signed_Bezier,
				quad_min = {a.x, inner_box.lo.y},
				quad_max = {mp.x, inner_box.hi.y},
				radius = 1,
				cv0 = a,
				cv1 = ab,
				cv2 = mp,
				paint = vgo.paint_index_from_option(paint),
			}
			shape1 := vgo.Shape{
				kind = .Signed_Bezier,
				quad_min = {mp.x, inner_box.lo.y},
				quad_max = {d.x, inner_box.hi.y},
				radius = -1,
				cv0 = d,
				cv1 = cd,
				cv2 = mp,
				paint = vgo.paint_index_from_option(paint),
			}
			vgo.add_shape(shape0)
			vgo.add_shape(shape1)
			shape0.outline = .Stroke
			shape1.outline = .Stroke
			shape0.width = 1
			shape1.width = 1
			shape0.paint = vgo.paint_index_from_option(color)
			shape1.paint = vgo.paint_index_from_option(color)
			vgo.add_shape(shape0)
			vgo.add_shape(shape1)
			// vgo.stroke_cubic_bezier(p1, c1, c2, p2, 2, paint = color)
		}

		if .Hovered in object.state.current && hn >= 0 && hn < len(data) {
			p :=
				inner_box.lo.x + (f32(hn) / f32(len(data) - 1)) * (inner_box.hi.x - inner_box.lo.x)
			vgo.fill_box({{p, inner_box.lo.y}, {p + 1, inner_box.hi.y}}, paint = colors().content)
		}

		// lp: [2]f32
		// for value, i in data {
		// 	point_time: f32 = f32(i) / f32(len(data) - 1)
		// 	p: [2]f32 = {
		// 		inner_box.lo.x + point_time * (inner_box.hi.x - inner_box.lo.x),
		// 		inner_box.hi.y +
		// 		(f32(value - low) / f32(high - low)) *
		// 			(inner_box.lo.y - inner_box.hi.y),
		// 	}
		// 	dot_time := f32(0)//variant.dot_times[e]
		// 	dot_time = animate(dot_time, 0.15, hn == i && .Hovered in object.state.current)
		// 	vgo.fill_circle(p, 4.5, color)
		// 	if dot_time > 0 {
		// 		vgo.fill_circle(p, 8 * dot_time, color)
		// 		vgo.fill_circle(p, 6 * dot_time, colors().foreground)
		// 	}
		// 	// variant.dot_times[e] = dot_time
		// 	lp = p
		// }
	}

	return true
}

/*
	object := persistent_object(hash(loc))

	begin_object(object) or_return
	defer end_object()

	object.box = next_box({})

	inner_box := object.box

	object.hover_time = animate(object.hover_time, 0.2, .Hovered in object.state.current)

	tooltip_idx: int
	tooltip_pos: Maybe([2]f32)

	switch kind in kind {
	case Line_Graph:


	case Bar_Graph:
		PADDING :: 5
		block_size: f32 = (inner_box.hi.x - inner_box.lo.x) / f32(len(data))
		tooltip_idx = clamp(
			int((global_state.mouse_pos.x - object.box.lo.x) / block_size),
			0,
			len(entries) - 1,
		)

		if .Hovered in object.state.current {
			vgo.fill_box(
				{
					{inner_box.lo.x + f32(tooltip_idx) * block_size, inner_box.lo.y},
					{inner_box.lo.x + f32(tooltip_idx) * block_size + block_size, inner_box.hi.y},
				},
				paint = vgo.fade(colors().substance, 0.5),
			)
		}

		if kind.stacked {

			for v := lo; v <= hi; v += increment / f64(len(fields)) {
				p := math.floor(
					inner_box.hi.y + (inner_box.lo.y - inner_box.hi.y) * (f32(v) / f32(hi - lo)),
				)
				vgo.fill_box(
					{{inner_box.lo.x, p}, {inner_box.hi.x, p + 1}},
					paint = vgo.fade(colors().substance, 0.5),
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
						16,
						{(block.lo.x + block.hi.x) / 2, block.hi.y + 2},
						font = global_state.style.default_font,
						paint = colors().content,
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
						global_state.style.rounding,
						paint = color,
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
					paint = vgo.fade(colors().substance, 0.5),
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
					vgo.fill_text(
						entry.label,
						18,
						{(block.lo.x + block.hi.x) / 2, block.hi.y + 2},
						font = global_state.style.default_font,
						align = {0.5, 0},
						paint = colors().content,
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
						{global_state.style.rounding, global_state.style.rounding, 0, 0},
						color,
					)
					if kind.value_labels {
						vgo.fill_text(
							fmt.tprint(entry.values[f]),
							18,
							origin = {(bar.lo.x + bar.hi.x) / 2, bar.lo.y - 2},
							font = global_state.style.default_font,
							align = 0.5,
							paint = vgo.fade(colors().content, 0.5 if entry.values[f] == 0 else 1.0),
						)
					}
				}
			}
		}
	}

	if .Hovered in object.state.current {
		tooltip_size: [2]f32 = {150, f32(len(fields)) * 26 + 6}
		if label_tooltip {
			tooltip_size += 26
		}
		// // Tooltip
		// begin_tooltip({bounds = object.box, size = tooltip_size})
		// add_padding(3)
		// if label_tooltip {
		// 	box := cut_current_layout(.Top, [2]f32{0, 26})
		// 	vgo.fill_text_aligned(
		// 		entries[tooltip_idx].label,
		// 		global_state.style.default_font,
		// 		18,
		// 		box.lo + [2]f32{5, 13},
		// 		.Center,
		// 		.Top,
		// 		paint = colors().content,
		// 	)
		// }
		// for &field, f in fields {
		// 	tip_box := shrink_box(cut_box(&current_layout().?.box, .Top, 26), 3)
		// 	blip_box := shrink_box(cut_box_left(&tip_box, box_height(tip_box)), 4)
		// 	vgo.fill_box(blip_box, paint = color)
		// 	vgo.fill_text_aligned(
		// 		field.name,
		// 		global_state.style.default_font,
		// 		18,
		// 		{tip_box.lo.x, (tip_box.lo.y + tip_box.hi.y) / 2},
		// 		.Left,
		// 		.Center,
		// 		paint = vgo.fade(colors().content, 0.5),
		// 	)
		// 	vgo.fill_text_aligned(
		// 		fmt.tprintf("%v", entries[tooltip_idx].values[f]),
		// 		global_state.style.default_font,
		// 		18,
		// 		{tip_box.hi.x, (tip_box.lo.y + tip_box.hi.y) / 2},
		// 		.Right,
		// 		.Center,
		// 		paint = colors().content,
		// 	)
		// }
		// end_tooltip()
	}

	if point_in_box(mouse_point(), object.box) {
		hover_object(object)
	}

	return true
}
*/
