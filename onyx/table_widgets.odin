package onyx
// Tables behave like a spreadsheet, need I say more?
import "core:fmt"
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

Table_Result :: struct {
	first, last: int,
}

Table_Widget_Kind :: struct {
	selection: [2][2]u64,
}

Table_Row :: struct {
	values: [][dynamic]u8,
}

Table_Data :: struct {
	rows: [dynamic]Table_Row,
}

// Begins a new row in the current table
begin_table_row :: proc(info: Table_Row_Info) {
	push_id(info.index + 1)
	layout := current_layout().?
	table_info := layout.table_info.?
	box := Box{
		{layout.bounds.lo.x, layout.bounds.lo.y + f32(info.index + 1) * core.style.table_row_height},
		{layout.bounds.hi.x, layout.bounds.lo.y + f32(info.index + 2) * core.style.table_row_height}
	}
	begin_layout({box = box})
	set_side(.Left)
	new_layout := current_layout().?
	new_layout.fixed = true
	new_layout.queue_len += copy(
		new_layout.size_queue[:],
		table_info.__widths[:table_info.__widths_len],
	)
}

end_table_row :: proc() {
	end_layout()
	pop_id()
}
// Make a new table
// 	This proc looks at the provided columns and decides the desired size of the table
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
		core.style.shape.table_row_height *
		f32(min(info.row_count, info.max_displayed_rows))
	return info
}
// Begin a table
begin_table :: proc(
	info: Table_Info,
	loc := #caller_location,
) -> (
	result: Table_Result,
	ok: bool,
) {
	info := make_table(info, loc)
	widget := begin_widget(info) or_return

	container := begin_container(
		{
			id = info.id.?,
			box = widget.box,
			size = {0, f32(info.row_count - 1) * core.style.table_row_height},
		},
	) or_return
	container.layout.table_info = info
	// Set first and last rows to be displayed
	result.first = int(container.scroll.y / core.style.table_row_height)
	result.last =
		min(result.first +
		int(box_height(container.box) / core.style.table_row_height), info.row_count)
	// Add space for the header
	add_space(f32(info.row_count - 1) * core.style.table_row_height)
	// Season the hashing context
	push_id(info.id.?)
	ok = true
	return
}
// End the current table
end_table :: proc() {
	table_info := current_layout().?.table_info.?
	container_layout := current_layout().?
	container := current_container().?
	box := container_layout.bounds

	// Selection highlight


	// Vertical dividing lines
	offset := f32(0)
	for i in 0 ..< table_info.__widths_len {
		if i > 0 {
			draw_box_fill(
				{
					{box.lo.x + offset, box.lo.y},
					{box.lo.x + offset + 1, box.hi.y},
				},
				core.style.color.substance,
			)
		}
		offset += table_info.__widths[i]
	}

	// Header
	header_box := get_box_cut_top(
		{
			{container_layout.bounds.lo.x, container.box.lo.y},
			{container_layout.bounds.hi.x, container.box.hi.y},
		},
		core.style.table_row_height,
	)
	// Background and lower border
	draw_box_fill(header_box, core.style.color.foreground)
	draw_box_fill(
		get_box_cut_bottom(header_box, 1),
		core.style.color.substance,
	)
	begin_layout({box = header_box})
	// Set layout sizes
	layout := current_layout().?
	set_side(.Left)
	layout.fixed = true
	layout.isolated = true
	layout.queue_len += copy(
		layout.size_queue[:],
		table_info.__widths[:table_info.__widths_len],
	)
	// set_height_fill()
	for &column, c in table_info.columns {
		widget := begin_widget({id = hash(c + 1)}) or_continue
		defer end_widget()
		button_behavior(widget)
		draw_text_glyphs(
			column.__label_text_job,
			box_center(widget.box),
			fade(core.style.color.content, 0.5),
		)
		if c > 0 {
			draw_box_fill(
				get_box_cut_left(widget.box, 1),
				core.style.color.substance,
			)
		}
	}
	end_layout()
	end_container()

	pop_id()

	// Table outline
	draw_rounded_box_stroke(
		current_widget().?.box,
		core.style.shape.rounding,
		1,
		core.style.color.substance,
	)

	end_widget()
}

@(deferred_out = __do_table)
do_table :: proc(info: Table_Info, loc := #caller_location) -> (self: Table_Result, ok: bool) {
	return begin_table(info, loc)
}

@(private)
__do_table :: proc(_: Table_Result, ok: bool) {
	if ok {
		end_table()
	}
}
