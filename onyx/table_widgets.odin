package onyx

import "base:runtime"
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
	name:           string,
	type:           Table_Column_Type,
	width:          f32,
	align:          Horizontal_Text_Align,
	label_text_job: Text_Job,
}
// Info needed to display a table row
Table_Row_Info :: struct {
	index:  int,
	active: bool,
}

Table_Info :: struct {
	using _:            Widget_Info,
	sort_order:         ^Sort_Order,
	sorted_column:      ^int,
	columns:            []Table_Column_Info,
	row_count:          int,
	max_displayed_rows: int,
	widths:             [24]f32,
	widths_len:         int,
	first, last:        int,
	sorted:             bool,
	cont_info:               Container_Info,
}

Table_Widget_Kind :: struct {
	selection: [2][2]u64,
}

// Begins a new row in the current table
begin_table_row :: proc(table_info: ^Table_Info, info: Table_Row_Info) {
	push_id(info.index + 1)
	begin_layout({side = .Top, size = core.style.table_row_height})
	layout := current_layout().?
	layout.next_cut_side = .Left
	layout.fixed = true
	layout.queue_len += copy(layout.size_queue[:], table_info.widths[:table_info.widths_len])

	if info.index % 2 == 1 {
		draw_box_fill(layout.bounds, fade(core.style.color.substance, 0.5))
	}
}

end_table_row :: proc() {
	end_layout()
	pop_id()
}

// Pass cell variables in rows, each variable will be assertively type checked with the column type
table_row :: proc(table_info: ^Table_Info, index: int, values: ..any) {
	for value, v in values {
		column := &table_info.columns[v]
		table_cell(v, index, value, column.type)
	}
}

table_cell :: proc(column, row: int, value: any, type: Table_Column_Type) {
	#partial switch type in type {
	case Type_Text:
		switch value.id {
		case string:
			string_input({value = (^string)(value.data)})
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
init_table :: proc(info: ^Table_Info, loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	for &column, c in info.columns {
		text: string = column.name
		if info.sorted_column != nil && info.sorted_column^ == c {
			if info.sort_order != nil {
				switch info.sort_order^ {
				case .Ascending:
					text = fmt.tprintf("%s \uEA78", column.name)
				case .Descending:
					text = fmt.tprintf("%s \uEA4E", column.name)
				}
			}
		}
		column.label_text_job =
		make_text_job(
			{
				text = text,
				font = core.style.default_font,
				size = core.style.button_text_size,
				align_h = .Middle,
				align_v = .Middle,
			},
		) or_continue
		column.width = max(column.width, column.label_text_job.size.x + 20)
		info.widths[c] = column.width
		info.desired_size.x += column.width
	}
	info.widths_len = len(info.columns)
	info.desired_size.y =
		core.style.shape.table_row_height * f32(min(info.row_count, info.max_displayed_rows))
	return true
}
// Begin a table
begin_table :: proc(using info: ^Table_Info, loc := #caller_location) -> bool {
	init_table(info, loc) or_return
	begin_widget(info) or_return

	push_id(info.id)
	defer pop_id()

	cont_info = Container_Info {
		id = hash("cont"),
		box = self.box,
		size = {1 = core.style.table_row_height * f32(info.row_count + 1)},
	}
	begin_container(&cont_info) or_return

	first = 0
	last = row_count - 1
	// first = int(container.scroll.y / core.style.table_row_height)
	// last = min(
	// 	first + int(math.ceil(box_height(self.box) / core.style.table_row_height)),
	// 	info.row_count - 1,
	// )
	// Add space for the header
	add_space(core.style.table_row_height * f32(first + 1))
	// Season the hashing context
	push_id(info.id)
	return true
}
// End the current table
end_table :: proc(using info: ^Table_Info) {
	// Header
	header_box := get_box_cut_top(
		{
			{cont_info.layout.bounds.lo.x, cont_info.self.box.lo.y},
			{cont_info.layout.bounds.hi.x, cont_info.self.box.hi.y},
		},
		core.style.table_row_height,
	)
	// Background and lower border
	draw_box_fill(
		header_box,
		alpha_blend_colors(core.style.color.foreground, core.style.color.substance, 0.5),
	)
	begin_layout({box = header_box})
	// Set layout sizes
	layout := current_layout().?
	layout.next_cut_side = .Left
	layout.fixed = true
	layout.isolated = true
	layout.queue_len += copy(layout.size_queue[:], info.widths[:info.widths_len])
	for &column, c in info.columns {
		using widget_info := Widget_Info {
			id = hash(c + 1),
		}
		begin_widget(&widget_info) or_continue
		defer end_widget()

		button_behavior(self)

		text_box := expand_box(
			{
				box_center(self.box) - column.label_text_job.size / 2,
				box_center(self.box) + column.label_text_job.size / 2,
			},
			3,
		)
		draw_rounded_box_fill(
			text_box,
			core.style.rounding,
			fade(core.style.color.substance, self.hover_time),
		)
		draw_text_glyphs(
			column.label_text_job,
			box_center(self.box),
			fade(core.style.color.content, 0.5),
		)

		if self.state >= {.Clicked} {
			if info.sorted_column != nil && info.sort_order != nil {
				if info.sorted_column^ == c {
					info.sort_order^ = Sort_Order((int(info.sort_order^) + 1) % len(Sort_Order))
				} else {
					info.sorted_column^ = c
				}
				info.sorted = true
			}
		}
	}
	end_layout()
	end_container(&cont_info)
	end_widget()
	pop_id()
}

@(deferred_in_out = __table)
table :: proc(info: ^Table_Info, loc := #caller_location) -> bool {
	return begin_table(info, loc)
}

@(private)
__table :: proc(info: ^Table_Info, _: runtime.Source_Code_Location, ok: bool) {
	if ok {
		end_table(info)
	}
}
