package onyx

import "core:fmt"
import "core:math"
import t "core:time"
import dt "core:time/datetime"

Date :: dt.Date

Calendar_Info :: struct {
	id:                Id,
	selection:         [2]Maybe(Date),
	desired_size:      [2]f32,
	month_offset:      int,
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

make_calendar :: proc(info: Calendar_Info, loc := #caller_location) -> Calendar_Info {
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
		t.datetime_to_time(dt.DateTime{info.selection[0].? or_else Date{}, {}}) or_else t.Time{},
		t.datetime_to_time(dt.DateTime{info.selection[1].? or_else Date{}, {}}) or_else t.Time{},
	}

	// Get the start of the month
	info.__month_start =
		t.datetime_to_time(i64(info.__year), i8(info.__month), 1, 0, 0, 0) or_else panic(
			"invalid date",
		)

	// Set the first date on the calendar to be the previous sunday
	weekday := t.weekday(info.__month_start)
	info.__calendar_start._nsec = info.__month_start._nsec - i64(weekday) * i64(t.Hour * 24)

	// Get number of days in this month
	days, _ := dt.last_day_of_month(i64(info.__year), i8(info.__month))

	// How many rows?
	info.__days = int(
		(info.__month_start._nsec - info.__calendar_start._nsec) / i64(t.Hour * 24) + i64(days),
	)
	info.__days = int(math.ceil(f32(info.__days) / 7)) * 7
	info.desired_size.y += f32(info.__days / 7) * info.__size

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

	if do_layout({side = .Top, size = size}) {
		set_padding(5)
		if was_clicked(do_button({text = "\uEA64", font_style = .Icon, kind = .Outlined})) {
			result.month_offset -= 1
		}
		set_side(.Right)
		if was_clicked(do_button({text = "\uEA6E", font_style = .Icon, kind = .Outlined})) {
			result.month_offset += 1
		}
		draw_text(
			box_center(layout_box()),
			{
				text = tmp_printf("%s %i", t.Month(info.__month), info.__year),
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

	add_space(4)

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

	add_space(4)

	// Days
	begin_layout({side = .Top, size = size})
	for i in 0 ..< info.__days {
		if (i > 0) && (i % 7 == 0) {
			end_layout()
			add_space(4)
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
			   time._nsec <= info.__selection_times[1]._nsec + i64(t.Hour * 24) {
				corners: Corners = {}
				if time._nsec == info.__selection_times[0]._nsec + i64(t.Hour * 24) {
					corners += {.Top_Left, .Bottom_Left}
				}
				if time._nsec == info.__selection_times[1]._nsec + i64(t.Hour * 24) {
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
					text = tmp_print(day),
					font = core.style.fonts[.Medium if is_month else .Regular],
					size = 18,
					align_v = .Middle,
					align_h = .Middle,
				},
				blend_colors(
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
			if result.selection[0] == nil {
				result.selection[0] = date
				result.month_offset = 0
			} else {
				if date == result.selection[0] || date == result.selection[1] {
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
		}
		end_widget()
	}
	end_layout()
	end_layout()
	pop_id()
	return
}

do_calendar :: proc(info: Calendar_Info, loc := #caller_location) -> Calendar_Result {
	return add_calendar(make_calendar(info, loc))
}

Date_Picker_Widget_Kind :: struct {
	month_offset: int,
}
