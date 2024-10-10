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
		t.datetime_to_time(i64(year), i8(month), 1, 0, 0, 0) or_else panic("invalid date")

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
		if button({text = "\uEA64", style = .Outlined}).clicked {
			month_offset -= 1
		}
		set_side(.Right)
		if button({text = "\uEA6E", style = .Outlined}).clicked {
			month_offset += 1
		}
		draw_text(
			box_center(layout_box()),
			{
				text = fmt.tprintf("%s %i", t.Month(info.month), info.year),
				font = core.style.default_font,
				size = 18,
				align_h = .Middle,
				align_v = .Middle,
			},
			core.style.color.content,
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
		draw_text(
			box_center(sub_box),
			{
				text = weekday,
				font = core.style.default_font,
				size = 18,
				align_h = .Middle,
				align_v = .Middle,
			},
			fade(core.style.color.content, 0.5),
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
				draw_rounded_box_corners_fill(
					self.box,
					corners,
					fade(core.style.color.substance, 1 if is_month else 0.5),
				)
			} else {
				// Hover box
				if self.hover_time > 0 {
					draw_rounded_box_fill(
						self.box,
						core.style.shape.rounding,
						fade(core.style.color.substance, self.hover_time),
					)
				}
				if date == todays_date() {
					draw_rounded_box_stroke(
						self.box,
						core.style.shape.rounding,
						1,
						core.style.color.substance,
					)
				}
			}
			// Focus box
			if self.focus_time > 0 {
				draw_rounded_box_fill(
					self.box,
					core.style.shape.rounding,
					fade(core.style.color.content, self.focus_time),
				)
			}
			// Day number
			draw_text(
				box_center(self.box),
				{
					text = fmt.tprint(day),
					font = core.style.default_font,
					size = 18,
					align_v = .Middle,
					align_h = .Middle,
				},
				lerp_colors(
					self.focus_time,
					core.style.color.content if is_month else fade(core.style.color.content, 0.5),
					core.style.color.background,
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
	using _:       Widget_Info,
	first, second: ^Maybe(Date),
}

Date_Picker_Widget_Kind :: struct {
	month_offset: int,
}

init_date_picker :: proc(info: ^Date_Picker_Info, loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	info.desired_size = core.style.visual_size
	return true
}

add_date_picker :: proc(using info: ^Date_Picker_Info) -> bool {
	if info.first == nil {
		return false
	}

	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	kind := widget_kind(self, Date_Picker_Widget_Kind)
	self.open_time = animate(self.open_time, 0.2, .Open in self.state)

	if self.visible {
		draw_rounded_box_fill(
			self.box,
			core.style.rounding,
			fade(core.style.color.substance, self.hover_time * 0.5),
		)
		draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.style.color.substance)

		b := strings.builder_make(context.temp_allocator)

		if first, ok := info.first.?; ok {
			fmt.sbprintf(&b, "{:2i}/{:2i}/{:4i}", first.month, first.day, first.year)
		}
		if info.second != nil {
			if second, ok := info.second.?; ok {
				fmt.sbprintf(&b, " - {:2i}/{:2i}/{:4i}", second.month, second.day, second.year)
			}
		}

		draw_text(
			[2]f32{self.box.lo.x + 7, box_center_y(self.box)},
			{
				text = strings.to_string(b),
				font = core.style.default_font,
				size = core.style.content_text_size,
				align_v = .Middle,
			},
			core.style.color.content,
		)
	}

	if .Open in self.state {
		calendar_info := Calendar_Info {
			id           = self.id,
			month_offset = kind.month_offset,
			selection    = {info.first^, info.second^ if info.second != nil else nil},
			allow_range  = info.second != nil,
		}
		init_calendar(&calendar_info, {})

		if layer, ok := layer(get_popup_layer_info(self, calendar_info.desired_size + core.style.menu_padding * 2, side = .Left)); ok {
			draw_shadow(layout_box(), self.open_time)
			foreground()
			shrink(core.style.menu_padding)
			set_width_auto()
			set_height_auto()
			add_calendar(&calendar_info)
			kind.month_offset = calendar_info.month_offset
			info.first^ = calendar_info.selection[0]
			if info.second != nil {
				if date, ok := calendar_info.selection[1].?; ok {
					info.second^ = date
				} else {
					info.second^ = calendar_info.selection[0]
				}
			}
			if layer.state & {.Hovered, .Focused} == {} && .Focused not_in self.state {
				self.state -= {.Open}
			}
		}
	} else {
		if .Pressed in (self.state - self.last_state) {
			self.state += {.Open}
			kind.month_offset = 0
		}
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
