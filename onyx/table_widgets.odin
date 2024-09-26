package onyx

import "core:fmt"
import "core:math"
import "core:strings"

Type_Text :: struct {}
Type_Number :: struct {
	precision: u8,
}
Type_Date :: struct {}
Type_Time :: struct {}
Type_Enum :: struct {}

Table_Column_Type :: union #no_nil {
	Type_Text,
	Type_Number,
	Type_Date,
	Type_Time,
	Type_Enum,
}

Sort_Order :: enum {
	Ascending,
	Descending,
}
// Column formating info
Table_Column_Info :: struct {
	name:             string,
	type:             Table_Column_Type,
	width:            f32,
	align:            Horizontal_Text_Align,
	sorted:           Maybe(Sort_Order),
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

Table_Widget_Kind :: struct {
	selection: [2][2]u64,
}

Table :: struct {
	using info:  Table_Info,
	first, last: int,
}

Table_Result :: struct {
	column_clicked: Maybe(int),
}

// Begins a new row in the current table
begin_table_row :: proc(table: Table, info: Table_Row_Info) {
	table := table
	push_id(info.index + 1)
	begin_layout({side = .Top, size = core.style.table_row_height})
	layout := current_layout().?
	layout.next_cut_side = .Left
	layout.fixed = true
	layout.queue_len += copy(
		layout.size_queue[:],
		table.info.__widths[:table.info.__widths_len],
	)

	if info.index % 2 == 1 {
		draw_box_fill(layout.bounds, fade(core.style.color.substance, 0.5))
	}
}

end_table_row :: proc() {
	end_layout()
	pop_id()
}

// Pass cell variables in rows, each variable will be assertively type checked with the column type
table_row :: proc(table: Table, index: int, values: ..any) {
	for value, v in values {
		column := &table.info.columns[v]
		table_cell(v, index, value, column.type)
	}
}

table_cell :: proc(column, row: int, value: any, type: Table_Column_Type) {
	#partial switch type in type {
	case Type_Text:
		switch value.id {
		case string:
			text_input({content = (^string)(value.data)})
		}
	case Type_Number:
		switch value.id {
		case i8, i16, i32, i64, i128, u8, u16, u32, u64, u128:

		case f16, f32, f64:

		}
	}
}
// Make a new table
// 	This proc looks at the provided columns and decides the desired size of the table
make_table :: proc(info: Table_Info, loc := #caller_location) -> Table_Info {
	info := info
	info.id = hash(loc)
	for &column, c in info.columns {
		text: string
		switch column.sorted {
		case nil:
			text = column.name
		case .Ascending:
			text = fmt.tprintf("%s \uEA78", column.name)
		case .Descending:
			text = fmt.tprintf("%s \uEA4E", column.name)
		}
		column.__label_text_job =
		make_text_job(
			{
				text = text,
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
	self: Table,
	ok: bool,
) {
	info := make_table(info, loc)
	widget := begin_widget(info) or_return

	container := begin_container(
		{
			id = info.id.?,
			box = widget.box,
			size = {1 = core.style.table_row_height * f32(info.row_count + 1)},
		},
	) or_return

	self.info = info
	self.first = int(container.scroll.y / core.style.table_row_height)
	self.last = min(
		self.first +
		int(
			math.ceil(box_height(container.box) / core.style.table_row_height),
		),
		info.row_count - 1,
	)
	// Add space for the header
	add_space(core.style.table_row_height * f32(self.first + 1))
	// Season the hashing context
	push_id(info.id.?)
	ok = true
	return
}
// End the current table
end_table :: proc(table: Table) {
	table := table
	container := current_container().?
	box := container.layout.bounds

	// Vertical dividing lines
	offset := f32(0)
	for i in 0 ..< table.info.__widths_len {
		if i > 0 {
			draw_box_fill(
				{
					{box.lo.x + offset, box.lo.y},
					{box.lo.x + offset + 1, box.hi.y},
				},
				core.style.color.substance,
			)
		}
		offset += table.info.__widths[i]
	}

	// Header
	header_box := get_box_cut_top(
		{
			{container.layout.bounds.lo.x, container.box.lo.y},
			{container.layout.bounds.hi.x, container.box.hi.y},
		},
		core.style.table_row_height,
	)
	// Background and lower border
	draw_box_fill(
		header_box,
		alpha_blend_colors(
			core.style.color.foreground,
			core.style.color.substance,
			0.5,
		),
	)
	draw_box_fill(
		get_box_cut_bottom(header_box, 1),
		core.style.color.substance,
	)
	begin_layout({box = header_box})
	// Set layout sizes
	layout := current_layout().?
	layout.next_cut_side = .Left
	layout.fixed = true
	layout.isolated = true
	layout.queue_len += copy(
		layout.size_queue[:],
		table.info.__widths[:table.info.__widths_len],
	)
	for &column, c in table.info.columns {
		widget := begin_widget({id = hash(c + 1)}) or_continue
		defer end_widget()
		button_behavior(widget)

		text_box := expand_box(
			{
				box_center(widget.box) - column.__label_text_job.size / 2,
				box_center(widget.box) + column.__label_text_job.size / 2,
			},
			3,
		)
		draw_rounded_box_fill(
			text_box,
			core.style.rounding,
			fade(core.style.color.substance, widget.hover_time),
		)
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
	end_widget()
	pop_id()
}

@(deferred_out = __do_table)
do_table :: proc(
	info: Table_Info,
	loc := #caller_location,
) -> (
	self: Table,
	ok: bool,
) {
	return begin_table(info, loc)
}

@(private)
__do_table :: proc(self: Table, ok: bool) {
	if ok {
		end_table(self)
	}
}
