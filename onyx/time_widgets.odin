package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:strings"
import t "core:time"
import dt "core:time/datetime"

Date :: dt.Date
CALENDAR_WEEK_SPACING :: 4

Calendar_Info :: struct {
	id:                Id,
	selection:         [2]Maybe(Date),
	desired_size:      [2]f32,
	month_offset:      int,
	allow_range:       bool,
	__calendar_start:  t.Time,
	__month_start:     t.Time,
	__size:            f32,
	__days:            int,
	__year, __month:   int,
	__selection_times: [2]t.Time,
}

Calendar_Result :: struct {
	using _:      Generic_Widget_Result,
	selection:    [2]Maybe(Date),
	month_offset: int,
}

todays_date :: proc() -> Date {
	year, month, day := t.date(t.now())
	return Date{i64(year), i8(month), i8(day)}
}

dates_are_equal :: proc(a, b: Date) -> bool {
	return a.year == b.year && a.month == b.month && a.day == b.day
}

make_calendar :: proc(
	info: Calendar_Info,
	loc := #caller_location,
) -> Calendar_Info {
	info := info
	info.id = hash(loc)

	info.desired_size.x = 280
	info.__size = info.desired_size.x / 7
	info.desired_size.y = info.__size * 2

	date := info.selection[0].? or_else todays_date()

	info.__month = int(date.month) + info.month_offset
	info.__year = int(date.year)
	for info.__month < 1 {
		info.__year -= 1
		info.__month += 12
	}
	for info.__month > 12 {
		info.__year += 1
		info.__month -= 12
	}

	info.__selection_times = {
		t.datetime_to_time(
			dt.DateTime{info.selection[0].? or_else Date{}, {}},
		) or_else t.Time{},
		t.datetime_to_time(
			dt.DateTime{info.selection[1].? or_else Date{}, {}},
		) or_else t.Time{},
	}

	// Get the start of the month
	info.__month_start =
		t.datetime_to_time(
			i64(info.__year),
			i8(info.__month),
			1,
			0,
			0,
			0,
		) or_else panic("invalid date")

	// Set the first date on the calendar to be the previous sunday
	weekday := t.weekday(info.__month_start)
	info.__calendar_start._nsec =
		info.__month_start._nsec - i64(weekday) * i64(t.Hour * 24)

	// Get number of days in this month
	days, _ := dt.last_day_of_month(i64(info.__year), i8(info.__month))

	// How many rows?
	info.__days = int(
		(info.__month_start._nsec - info.__calendar_start._nsec) /
			i64(t.Hour * 24) +
		i64(days),
	)
	info.__days = int(math.ceil(f32(info.__days) / 7)) * 7
	weeks := math.ceil(f32(info.__days) / 7)
	info.desired_size.y +=
		weeks * info.__size + (weeks + 1) * CALENDAR_WEEK_SPACING

	return info
}

add_calendar :: proc(info: Calendar_Info) -> (result: Calendar_Result) {
	push_id(info.id)
	begin_layout({box = next_widget_box({desired_size = info.desired_size})})

	size := info.__size
	result.selection = info.selection
	result.month_offset = info.month_offset

	set_width(size)
	set_height(size)
	set_side(.Top)

	if layout({side = .Top, size = size}) {
		set_padding(5)
		if was_clicked(
			button({text = "\uEA64", font_style = .Icon, kind = .Outlined}),
		) {
			result.month_offset -= 1
		}
		set_side(.Right)
		if was_clicked(
			button({text = "\uEA6E", font_style = .Icon, kind = .Outlined}),
		) {
			result.month_offset += 1
		}
		draw_text(
			box_center(layout_box()),
			{
				text = fmt.tprintf(
					"%s %i",
					t.Month(info.__month),
					info.__year,
				),
				font = core.style.fonts[.Medium],
				size = 18,
				align_h = .Middle,
				align_v = .Middle,
			},
			core.style.color.content,
		)
		// if core.mouse_scroll.y != 0 {
		// 	result.month_offset += int(core.mouse_scroll.y)
		// 	core.draw_next_frame = true
		// }
	}

	add_space(CALENDAR_WEEK_SPACING)

	box := cut_current_layout(.Top, size)

	// Weekday names
	weekdays := [?]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
	for weekday in weekdays {
		sub_box := cut_box_left(&box, size)
		draw_text(
			box_center(sub_box),
			{
				text = weekday,
				font = core.style.fonts[.Regular],
				size = 18,
				align_h = .Middle,
				align_v = .Middle,
			},
			fade(core.style.color.content, 0.5),
		)
	}


	time := info.__calendar_start

	add_space(CALENDAR_WEEK_SPACING)

	// Days
	begin_layout({side = .Top, size = size})
	for i in 0 ..< info.__days {
		if (i > 0) && (i % 7 == 0) {
			end_layout()
			add_space(CALENDAR_WEEK_SPACING)
			begin_layout({side = .Top, size = size})
			set_side(.Left)
		}
		year, month, day := t.date(time)
		date := Date{i64(year), i8(month), i8(day)}
		time._nsec += i64(t.Hour * 24)

		today_year, today_month, today_day := t.date(t.now())

		widget, ok := begin_widget({id = hash(i)})
		if !ok do continue

		if widget.visible {
			is_month := i8(month) == i8(info.__month)
			// Range highlight
			if time._nsec > info.__selection_times[0]._nsec &&
			   time._nsec <=
				   info.__selection_times[1]._nsec + i64(t.Hour * 24) {
				corners: Corners = {}
				if time._nsec ==
				   info.__selection_times[0]._nsec + i64(t.Hour * 24) {
					corners += {.Top_Left, .Bottom_Left}
				}
				if time._nsec ==
				   info.__selection_times[1]._nsec + i64(t.Hour * 24) {
					corners += {.Top_Right, .Bottom_Right}
				}
				draw_rounded_box_corners_fill(
					widget.box,
					core.style.shape.rounding,
					corners,
					fade(core.style.color.substance, 1 if is_month else 0.5),
				)
			} else {
				// Hover box
				if widget.hover_time > 0 {
					draw_rounded_box_fill(
						widget.box,
						core.style.shape.rounding,
						fade(core.style.color.substance, widget.hover_time),
					)
				}
				if date == todays_date() {
					draw_rounded_box_stroke(
						widget.box,
						core.style.shape.rounding,
						1,
						core.style.color.substance,
					)
				}
			}
			// Focus box
			if widget.focus_time > 0 {
				draw_rounded_box_fill(
					widget.box,
					core.style.shape.rounding,
					fade(core.style.color.content, widget.focus_time),
				)
			}
			// Day number
			draw_text(
				box_center(widget.box),
				{
					text = fmt.tprint(day),
					font = core.style.fonts[.Medium if is_month else .Regular],
					size = 18,
					align_v = .Middle,
					align_h = .Middle,
				},
				interpolate_colors(
					widget.focus_time,
					core.style.color.content if is_month else fade(core.style.color.content, 0.5),
					core.style.color.background,
				),
			)
		}

		widget.focus_time = animate(
			widget.focus_time,
			0.2,
			date == info.selection[0] || date == info.selection[1],
		)

		button_behavior(widget)

		if .Clicked in widget.state {
			if info.allow_range {
				if result.selection[0] == nil {
					result.selection[0] = date
					result.month_offset = 0
				} else {
					if date == result.selection[0] ||
					   date == result.selection[1] {
						result.selection = {nil, nil}
					} else {
						if time._nsec <=
						   (t.datetime_to_time(dt.DateTime{result.selection[0].?, {}}) or_else t.Time{})._nsec {
							result.selection[0] = date
							result.month_offset = 0
						} else {
							result.selection[1] = date
						}
					}
				}
			} else {
				result.selection[0] = date
			}
		}
		end_widget()
	}
	end_layout()
	end_layout()
	pop_id()
	return
}

do_calendar :: proc(
	info: Calendar_Info,
	loc := #caller_location,
) -> Calendar_Result {
	return add_calendar(make_calendar(info, loc))
}

Date_Picker_Info :: struct {
	using _:       Generic_Widget_Info,
	first, second: ^Maybe(Date),
}

Date_Picker_Result :: struct {
	using _: Generic_Widget_Result,
}

Date_Picker_Widget_Kind :: struct {
	using _:      Menu_Widget_Kind,
	month_offset: int,
}

make_date_picker :: proc(
	info: Date_Picker_Info,
	loc := #caller_location,
) -> Date_Picker_Info {
	info := info
	info.id = hash(loc)
	info.desired_size = core.style.visual_size
	return info
}

add_date_picker :: proc(
	info: Date_Picker_Info,
) -> (
	result: Date_Picker_Result,
) {
	if info.first == nil {
		return
	}

	widget, ok := begin_widget(info)
	if !ok do return
	defer end_widget()

	result.self = widget

	button_behavior(widget)

	kind := widget_kind(widget, Date_Picker_Widget_Kind)

	kind.open_time = animate(kind.open_time, 0.2, .Open in widget.state)

	if widget.visible {
		draw_rounded_box_fill(
			widget.box,
			core.style.rounding,
			fade(core.style.color.substance, widget.hover_time),
		)
		if widget.hover_time < 1 {
			draw_rounded_box_stroke(
				widget.box,
				core.style.rounding,
				1,
				core.style.color.substance,
			)
		}

		b := strings.builder_make(context.temp_allocator)

		if first, ok := info.first.?; ok {
			fmt.sbprintf(
				&b,
				"{:2i}/{:2i}/{:4i}",
				first.month,
				first.day,
				first.year,
			)
		}
		if info.second != nil {
			if second, ok := info.second.?; ok {
				fmt.sbprintf(
					&b,
					" - {:2i}/{:2i}/{:4i}",
					second.month,
					second.day,
					second.year,
				)
			}
		}

		draw_text(
			[2]f32{widget.box.lo.x + 7, box_center_y(widget.box)},
			{
				text = strings.to_string(b),
				font = core.style.fonts[.Regular],
				size = core.style.content_text_size,
				align_v = .Middle,
			},
			core.style.color.content,
		)
	}

	if .Open in widget.state {
		calendar_info := make_calendar(
			{
				id = widget.id,
				month_offset = kind.month_offset,
				selection = {
					info.first^,
					info.second^ if info.second != nil else nil,
				},
				allow_range = info.second != nil,
			},
		)

		layer_box := get_menu_box(
			widget.box,
			calendar_info.desired_size + core.style.menu_padding * 2,
		)

		open_time := ease.quadratic_out(kind.open_time)
		scale: f32 = 0.85 + 0.15 * open_time

		if layer, ok := layer(
			{
				id = widget.id,
				origin = layer_box.lo,
				box = layer_box,
				opacity = open_time,
				scale = [2]f32{scale, scale},
			},
		); ok {
			foreground()
			shrink(core.style.menu_padding)
			set_width_auto()
			set_height_auto()
			calendar_result := add_calendar(calendar_info)
			kind.month_offset = calendar_result.month_offset
			info.first^ = calendar_result.selection[0]
			if info.second != nil {
				if date, ok := calendar_result.selection[1].?; ok {
					info.second^ = date
				} else {
					info.second^ = calendar_result.selection[0]
				}
			}
			if layer.state & {.Hovered, .Focused} == {} &&
			   .Focused not_in widget.state {
				widget.state -= {.Open}
			}
		}
	} else {
		if .Pressed in (widget.state - widget.last_state) {
			widget.state += {.Open}
			kind.month_offset = 0
		}
	}

	return
}

date_picker :: proc(
	info: Date_Picker_Info,
	loc := #caller_location,
) -> Date_Picker_Result {
	return add_date_picker(make_date_picker(info, loc))
}
