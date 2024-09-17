package onyx

import "core:math"

// Column formating info
Table_Column_Info :: struct {
	name:             string,
	width:            f32,
	align:            Horizontal_Text_Align,
	__label_text_job: Text_Job,
}
// Info needed to display a table row
Table_Row_Info :: struct {
	index:  int,
	active: bool,
}

Table_Info :: struct {
	using _:            Generic_Widget_Info,
	columns:            []Table_Column_Info,
	row_count:          int,
	max_displayed_rows: int,
	__widths:           [24]f32,
	__widths_len:       int,
}

// Begins a new row in the current table
// 	This is essentially a wrapper for whatever widgets are used to display or
// 	edit the table data.
begin_table_row :: proc(info: Table_Row_Info) {
	push_id(info.index)
	table_info := current_layout().?.table_info.?
	begin_layout({side = .Top, size = core.style.table_row_height})
	set_side(.Left)
	layout := current_layout().?
	layout.fixed = true
	layout.queue_len += copy(layout.size_queue[:], table_info.__widths[:table_info.__widths_len])
}

end_table_row :: proc() {
	end_layout()
	pop_id()
}

make_table :: proc(info: Table_Info, loc := #caller_location) -> Table_Info {
	info := info
	info.id = hash(loc)
	for &column, c in info.columns {
		column.__label_text_job =
		make_text_job(
			{
				text = column.name,
				font = core.style.fonts[.Medium],
				size = core.style.button_text_size,
				align_h = .Middle,
				align_v = .Middle,
			},
		) or_continue
		column.width = max(column.width, column.__label_text_job.size.x + 20)
		info.__widths[c] = column.width
		info.desired_size.x += column.width
	}
	info.__widths_len = len(info.columns)
	info.desired_size.y =
		core.style.shape.table_row_height * f32(min(info.row_count, info.max_displayed_rows) + 1)
	return info
}

// Begin a new table
// 	This proc looks at the provided columns and decides the desired size of the table
// 	then pushes a new container of that size.  The number of rows can optionally be
// 	defined.
begin_table :: proc(info: Table_Info, loc := #caller_location) -> (ok: bool) {
	info := make_table(info, loc)
	widget := begin_widget(info) or_return

	begin_container({id = info.id.?, box = widget.box, size = {0, f32(info.row_count) * core.style.table_row_height}}) or_return
	current_layout().?.table_info = info
	cut_layout(current_layout().?, .Top, core.style.table_row_height)
	push_id(info.id.?)
	ok = true
	return
}

// End the current table
end_table :: proc() {
	table_info := current_layout().?.table_info.?
	box := current_layout().?.bounds
	cnt := current_container().?
	offset := f32(0)
	for i in 0..<table_info.__widths_len {
		if i > 0 {
			// draw_box_fill({{box.lo.x + offset, box.lo.y}, {box.lo.x + offset + 1, box.hi.y}}, core.style.color.substance)
		}
		offset += table_info.__widths[i]
	}

	// Header
	bax := get_box_cut_top(box, core.style.table_row_height)
	// Background and lower border
	draw_box_fill(bax, core.style.color.foreground)
	draw_box_fill(get_box_cut_bottom(bax, 1), core.style.color.substance)
	begin_layout({box = bax})
	// Set layout sizes
	layout := current_layout().?
	set_side(.Left)
	layout.fixed = true
	layout.isolated = true
	layout.queue_len += copy(layout.size_queue[:], table_info.__widths[:table_info.__widths_len])
	// set_height_fill()
	for &column, c in table_info.columns {
		widget := begin_widget({id = hash(c + 1)}) or_continue
		defer end_widget()
		button_behavior(widget)
		draw_text_glyphs(column.__label_text_job, box_center(widget.box), fade(core.style.color.content, 0.5))
		if c > 0 {
			draw_box_fill(get_box_cut_left(widget.box, 1), core.style.color.substance)
		}
	}
	end_layout()
	end_container()

	pop_id()

	// Table outline
	draw_rounded_box_stroke(current_widget().?.box, core.style.shape.rounding, 1, core.style.color.substance)

	end_widget()
}

@(deferred_out = __do_table)
do_table :: proc(info: Table_Info, loc := #caller_location) -> (ok: bool) {
	return begin_table(info, loc)
}

@(private)
__do_table :: proc(ok: bool) {
	if ok {
		end_table()
	}
}
