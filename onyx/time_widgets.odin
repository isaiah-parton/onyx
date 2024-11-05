package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:strings"
import "core:strconv"
import t "core:time"
import dt "core:time/datetime"
import "../../vgo"

Date :: dt.Date
CALENDAR_WEEK_SPACING :: 4

Calendar_Info :: struct {
	using _:         Widget_Info,
	selection:       [2]Maybe(Date),
	month_offset:    int,
	allow_range:     bool,
	calendar_start:  t.Time,
	month_start:     t.Time,
	size:            f32,
	days:            int,
	year:            int,
	month:           int,
	selection_times: [2]t.Time,
}

todays_date :: proc() -> Date {
	year, month, day := t.date(t.now())
	return Date{i64(year), i8(month), i8(day)}
}

dates_are_equal :: proc(a, b: Date) -> bool {
	return a.year == b.year && a.month == b.month && a.day == b.day
}

init_calendar :: proc(using info: ^Calendar_Info, loc := #caller_location) -> bool {
	id = hash(loc)
	desired_size.x = 280
	size = desired_size.x / 7
	desired_size.y = size * 2

	date := selection[0].? or_else todays_date()

	month = int(date.month) + month_offset
	year = int(date.year)
	for month < 1 {
		year -= 1
		month += 12
	}
	for month > 12 {
		year += 1
		month -= 12
	}

	selection_times = {
		t.datetime_to_time(dt.DateTime{selection[0].? or_else Date{}, {}}) or_else t.Time{},
		t.datetime_to_time(dt.DateTime{selection[1].? or_else Date{}, {}}) or_else t.Time{},
	}

	// Get the start of the month
	month_start =
		t.datetime_to_time(i64(year), i8(month), 1, 0, 0, 0) or_return

	// Set the first date on the calendar to be the previous sunday
	weekday := t.weekday(month_start)
	calendar_start._nsec = month_start._nsec - i64(weekday) * i64(t.Hour * 24)

	// Get number of days in this month
	if _days, err := dt.last_day_of_month(i64(year), i8(month)); err == nil {
		days = int(_days)
	}

	// How many rows?
	days = int((month_start._nsec - calendar_start._nsec) / i64(t.Hour * 24) + i64(days))
	days = int(math.ceil(f32(days) / 7)) * 7
	weeks := math.ceil(f32(days) / 7)
	desired_size.y += weeks * size + (weeks + 1) * CALENDAR_WEEK_SPACING

	return true
}

add_calendar :: proc(using info: ^Calendar_Info) -> bool {
	push_id(id)
	begin_layout({box = next_widget_box(info)})

	set_width(size)
	set_height(size)
	set_side(.Top)

	if layout({side = .Top, size = size}) {
		set_padding(5)
		left_btn := button({style = .Outlined})
		set_side(.Right)
		right_btn := button({style = .Outlined})
		vgo.arrow(box_center(left_btn.self.box), 5, angle = math.PI, paint = core.style.color.content)
		vgo.arrow(box_center(right_btn.self.box), 5, paint = core.style.color.content)
		if left_btn.clicked {
			month_offset -= 1
		}
		if right_btn.clicked {
			month_offset += 1
		}
		vgo.fill_text_aligned(
			fmt.tprintf("%s %i", t.Month(info.month), info.year),
			core.style.default_font,
			core.style.default_text_size,
			box_center(layout_box()),
			.Center,
			.Center,
			paint = core.style.color.content,
		)
		// if core.mouse_scroll.y != 0 {
		// 	month_offset += int(core.mouse_scroll.y)
		// 	core.draw_next_frame = true
		// }
	}

	add_space(CALENDAR_WEEK_SPACING)

	layout_box := cut_current_layout(.Top, size)

	// Weekday names
	weekdays := [?]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
	for weekday in weekdays {
		sub_box := cut_box_left(&layout_box, size)
		vgo.fill_text_aligned(
			weekday,
			core.style.default_font,
			core.style.default_text_size,
			box_center(sub_box),
			.Center,
			.Center,
			paint = vgo.fade(core.style.color.content, 0.5),
		)
	}

	time := info.calendar_start

	add_space(CALENDAR_WEEK_SPACING)

	// Days
	begin_layout({side = .Top, size = size})
	for i in 0 ..< info.days {
		if (i > 0) && (i % 7 == 0) {
			end_layout()
			add_space(CALENDAR_WEEK_SPACING)
			begin_layout({side = .Top, size = size})
			set_side(.Left)
			set_mode(.Absolute)
		}
		year, month, day := t.date(time)
		date := Date{i64(year), i8(month), i8(day)}
		time._nsec += i64(t.Hour * 24)

		today_year, today_month, today_day := t.date(t.now())

		using widget_info := Widget_Info {
			id = hash(i + 1),
		}
		begin_widget(&widget_info) or_continue

		if self.visible {
			is_month := i8(month) == i8(info.month)
			// Range highlight
			if time._nsec > selection_times[0]._nsec &&
			   time._nsec <= selection_times[1]._nsec + i64(t.Hour * 24) {
				corners: [4]f32
				if time._nsec == selection_times[0]._nsec + i64(t.Hour * 24) {
					corners[0] = core.style.rounding
					corners[2] = core.style.rounding
				}
				if time._nsec == selection_times[1]._nsec + i64(t.Hour * 24) {
					corners[1] = core.style.rounding
					corners[3] = core.style.rounding
				}
				vgo.fill_box(
					self.box,
					corners,
					vgo.fade(core.style.color.substance, 1 if is_month else 0.5),
				)
			} else {
				// Hover box
				if self.hover_time > 0 {
					vgo.fill_box(
						self.box,
						core.style.shape.rounding,
						vgo.fade(core.style.color.substance, self.hover_time),
					)
				}
				if date == todays_date() {
					vgo.stroke_box(
						self.box,
						1,
						core.style.shape.rounding,
						core.style.color.substance,
					)
				}
			}
			// Focus box
			if self.focus_time > 0 {
				vgo.fill_box(
					self.box,
					core.style.shape.rounding,
					vgo.fade(core.style.color.content, self.focus_time),
				)
			}
			// Day number
			vgo.fill_text_aligned(
				fmt.tprint(day),
				core.style.default_font,
				core.style.default_text_size,
				box_center(self.box),
				.Center,
				.Center,
				paint = vgo.mix(
					self.focus_time,
					core.style.color.content if is_month else vgo.fade(core.style.color.content, 0.5),
					core.style.color.field,
				),
			)
		}

		self.focus_time = animate(
			self.focus_time,
			0.2,
			date == selection[0] || date == selection[1],
		)

		button_behavior(self)

		if .Clicked in self.state {
			if info.allow_range {
				if selection[0] == nil {
					selection[0] = date
				} else {
					if date == selection[0] || date == selection[1] {
						selection = {nil, nil}
					} else {
						if time._nsec <=
						   (t.datetime_to_time(dt.DateTime{selection[0].?, {}}) or_else t.Time{})._nsec {
							selection[0] = date
						} else {
							selection[1] = date
						}
					}
				}
			} else {
				selection[0] = date
			}
			month_offset = 0
		}
		end_widget()
	}
	end_layout()
	end_layout()
	pop_id()
	return true
}

calendar :: proc(info: Calendar_Info, loc := #caller_location) -> Calendar_Info {
	info := info
	if init_calendar(&info, loc) {
		add_calendar(&info)
	}
	return info
}

Date_Picker_Info :: struct {
	using _:       Input_Info,
	first, second: ^Maybe(Date),
}

Date_Picker_Widget_Kind :: struct {
	month_offset: int,
}

init_date_picker :: proc(info: ^Date_Picker_Info, loc := #caller_location) -> bool {
	init_input(info, loc) or_return
	if info.builder == nil {
		info.builder = &info.self.input.builder
	}
	if first, ok := info.first.?; ok {
		info.text = fmt.tprintf("%2i/%2i/%4i", first.month, first.day, first.year)
	}
	if .Active in (info.self.state - info.self.last_state) {
		strings.builder_reset(info.builder)
		strings.write_string(info.builder, info.text)
	}
	info.monospace = true
	return true
}

parse_date :: proc(s: string) -> (date: Date, ok: bool) {
	values := strings.split(s, "/")
	defer delete(values)
	if len(values) != 3 do return
	date.month = i8(strconv.parse_uint(values[0]) or_return)
	date.year = i64(strconv.parse_uint(values[2]) or_return)
	date.day = i8(strconv.parse_uint(values[1]) or_return)
	err := dt.validate_date(date)
	if err != nil do return
	ok = true
	return
}

add_date_picker :: proc(using info: ^Date_Picker_Info) -> bool {
	if info.first == nil {
		return false
	}

	add_input(info)

	if .Open in self.last_state {
		calendar_info := Calendar_Info {
			id           = self.id,
			month_offset = self.date.month_offset,
			selection    = {info.first^, info.second^ if info.second != nil else nil},
			allow_range  = info.second != nil,
		}
		init_calendar(&calendar_info, {})

		menu_layer := get_popup_layer_info(self, calendar_info.desired_size + core.style.menu_padding * 2, side = .Left)
		menu_layer.scale = nil
		if layer(&menu_layer) {
			draw_shadow(layout_box())
			foreground()
			add_padding(core.style.menu_padding)
			set_width_auto()
			set_height_auto()
			add_calendar(&calendar_info)
			self.date.month_offset = calendar_info.month_offset
			info.first^ = calendar_info.selection[0]
			if info.second != nil {
				if date, ok := calendar_info.selection[1].?; ok {
					info.second^ = date
				} else {
					info.second^ = calendar_info.selection[0]
				}
			}
			if menu_layer.self.state & {.Hovered, .Focused} == {} && .Focused not_in self.state {
				self.state -= {.Open}
			}
		}
	} else {
		if .Pressed in (self.state - self.last_state) {
			self.state += {.Open}
			self.date.month_offset = 0
		}
	}

	if changed {
		if date, ok := parse_date(text); ok {
			first^ = date
		} else {
			first^ = nil
		}
		core.draw_next_frame = true
	}

	return true
}

date_picker :: proc(info: Date_Picker_Info, loc := #caller_location) -> Date_Picker_Info {
	info := info
	if init_date_picker(&info, loc) {
		add_date_picker(&info)
	}
	return info
}
