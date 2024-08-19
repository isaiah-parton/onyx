package onyx

import "core:fmt"
import "core:math"
import t "core:time"
import dt "core:time/datetime"

Date :: dt.Date

Calendar_Info :: struct {
	id: Id,
	month_offset: int,
	range: [2]Date,
	desired_size: [2]f32,
	__calendar_start: t.Time,
	__month_start: t.Time,
	__size: f32,
	__days: int,
	__year, __month: int,
}

Calendar_Result :: struct {
	using _: Generic_Widget_Result,
	range: [2]Date,
	month_offset: int,
}

make_calendar :: proc(info: Calendar_Info, loc := #caller_location) -> Calendar_Info {
	info := info
	info.id = hash(loc)

	info.desired_size.x = 280
	info.__size = info.desired_size.x / 7
	info.desired_size.y = info.__size * 2

	info.__month = int(info.range[0].month) + info.month_offset
	info.__year = int(info.range[0].year)
	for info.__month < 1 {
		info.__year -= 1
		info.__month += 12
	}
	for info.__month > 12 {
		info.__year += 1
		info.__month -= 12
	}

	// Get the start of the month
	info.__month_start = t.datetime_to_time(i64(info.__year), i8(info.__month), 1, 0, 0, 0) or_else panic("invalid date")

	// Set the first date on the calendar to be the previous sunday
	weekday := t.weekday(info.__month_start)
	info.__calendar_start._nsec = info.__month_start._nsec - i64(weekday) * i64(t.Hour * 24)

	// Get number of days in this month
	days, _ := dt.last_day_of_month(i64(info.__year), i8(info.__month))

	// How many rows?
	info.__days = int((info.__month_start._nsec - info.__calendar_start._nsec) / i64(t.Hour * 24) + i64(days))
	info.__days = int(math.ceil(f32(info.__days) / 7)) * 7
	info.desired_size.y += f32(info.__days / 7) * info.__size 

	return info
}

add_calendar :: proc(info: Calendar_Info) -> (result: Calendar_Result) {
	push_id(info.id)
	begin_layout({box = next_widget_box({desired_size = info.desired_size})})

	size := info.__size
	result.range = info.range
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
		draw_text(box_center(layout_box()), {text = tmp_printf("%s %i", t.Month(info.__month), info.__year), font = core.style.fonts[.Medium], size = 18, align_h = .Middle, align_v = .Middle}, core.style.color.content)
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
		draw_text(box_center(sub_box), {text = weekday, font = core.style.fonts[.Regular], size = 18, align_h = .Middle, align_v = .Middle}, fade(core.style.color.content, 0.5))
	}

	
	time := info.__calendar_start

	add_space(4)

	// Days
	begin_layout({side = .Top, size = size})
	for i in 0..<info.__days {
		if (i > 0) && (i % 7 == 0) {
			end_layout()
			add_space(4)
			begin_layout({side = .Top, size = size})
			set_side(.Left)
		}
		year, month, day := t.date(time)
		time._nsec += i64(t.Hour * 24)

		today_year, today_month, today_day := t.date(t.now())
		
		widget, ok := begin_widget({id = hash(i)})
		if !ok do continue

		if widget.visible {
			draw_rounded_box_fill(widget.box, core.style.shape.rounding, blend_colors(widget.focus_time, fade(core.style.color.substance, widget.hover_time), core.style.color.content))
			draw_text(
				box_center(widget.box), 
				{
					text = tmp_print(day), 
					font = core.style.fonts[.Medium if i8(month) + 1 == info.range[0].month else .Regular], 
					size = 18, 
					align_v = .Middle, 
					align_h = .Middle,
				}, 
				blend_colors(
					widget.focus_time, 
					core.style.color.content if i8(month) == i8(info.__month) else fade(core.style.color.content, 0.5),
					core.style.color.background,
				),
			)
		}

		widget.focus_time = animate(widget.focus_time, 0.2, i64(year) == i64(info.range[0].year) && i8(month) == i8(info.range[0].month) && i8(day) == info.range[0].day)

		button_behavior(widget)
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