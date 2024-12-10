package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:strconv"
import "core:strings"
import t "core:time"
import dt "core:time/datetime"

Date :: dt.Date
CALENDAR_WEEK_SPACING :: 4

Calendar :: struct {
	using object:    ^Object,
	selection:       [2]Maybe(Date),
	month_offset:    int,
	allow_range:     bool,
	calendar_start:  t.Time,
	month_start:     t.Time,
	row_height:      f32,
	focus_time:      f32,
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

calendar :: proc(date: ^Maybe(Date), until: ^Maybe(Date) = nil, loc := #caller_location) {
	assert(date != nil, loc = loc)
	object := persistent_object(hash(loc))

	DAYS_PER_WEEK :: 7
	MONTHS_PER_YEAR :: 12
	HOURS_PER_DAY :: 24

	if object.variant == nil {
		object.variant = Calendar {
			object = object,
		}
	}
	self := &object.variant.(Calendar)
	self.metrics.desired_size = {280, 0}

	self.row_height = self.metrics.desired_size.x / DAYS_PER_WEEK
	self.metrics.desired_size.y = self.row_height * 2

	date := date.? or_else todays_date()

	month := int(date.month) + self.month_offset
	year := int(date.year)

	month_underflow := 1 - min(1, 1 + month)
	year -= 1 * month_underflow
	month += MONTHS_PER_YEAR * month_underflow

	year_overflow := max(0, month / MONTHS_PER_YEAR)
	year += 1 * year_overflow
	month -= MONTHS_PER_YEAR * year_overflow

	self.selection_times = {
		t.datetime_to_time(
			dt.DateTime{self.selection[0].? or_else Date{}, {}},
		) or_else t.Time{},
		t.datetime_to_time(
			dt.DateTime{self.selection[1].? or_else Date{}, {}},
		) or_else t.Time{},
	}

	month_start := t.datetime_to_time(i64(year), i8(month), 1, 0, 0, 0) or_else t.Time{}

	weekday := t.weekday(month_start)
	calendar_start := month_start._nsec - i64(weekday) * i64(t.Hour * HOURS_PER_DAY)

	self.days = 0
	if _days, err := dt.last_day_of_month(i64(year), i8(month)); err == nil {
		self.days = int(_days)
	}

	self.days = int(
		(month_start._nsec - calendar_start) / i64(t.Hour * HOURS_PER_DAY) + i64(self.days),
	)
	self.days = int(math.ceil(f32(self.days) / DAYS_PER_WEEK)) * DAYS_PER_WEEK
	weeks := math.ceil(f32(self.days) / DAYS_PER_WEEK)
	self.metrics.desired_size.y +=
		weeks * self.row_height + (weeks + 1) * CALENDAR_WEEK_SPACING

	self.content.side = .Top
	self.placement = next_user_placement()

	if begin_object(self) {
		defer end_object()

		push_id(self.id)
		defer pop_id()

		push_placement_options()
		defer pop_placement_options()

		if begin_row_layout(size = Fixed(self.row_height), justify = .Equal_Space) {
			defer end_layout()

			if button(text = "<", style = .Outlined).clicked {
				self.month_offset -= 1
			}
			label(text = fmt.tprintf("%s %i", t.Month(month), year))
			if button(text = ">", style = .Outlined).clicked {
				self.month_offset += 1
			}
		}

		if begin_row_layout(size = Fixed(self.row_height), justify = .Equal_Space) {
			defer end_layout()

			set_height(Percent(100))
			WEEKDAY_ABBREVIATIONS :: [?]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
			for weekday in WEEKDAY_ABBREVIATIONS {
				label(text = weekday)
			}
		}

		set_height(Percent(100))
		set_width(Percent_Of_Height(100))

		if begin_row_layout(size = Fixed(self.row_height)) {
			defer end_layout()

			time: t.Time = self.calendar_start
			for i in 0 ..< self.days {
				push_id(i + 1)
				defer pop_id()

				if (i > 0) && (i % 7 == 0) {
					end_layout()
					begin_row_layout(size = Fixed(self.row_height))
				}

				year, _month, day := t.date(time)
				date := Date{i64(year), i8(_month), i8(day)}
				time._nsec += i64(t.Hour * 24)

				today_year, today_month, today_day := t.date(t.now())

				calendar_day(day, today_year == year && today_month == _month && today_day == day, month == int(_month), time, {}, 0)

				// if .Clicked in self.state.current {
				// 	if self.allow_range {
				// 		if self.selection[0] == nil {
				// 			self.selection[0] = date
				// 		} else {
				// 			if date == self.selection[0] || date == self.selection[1] {
				// 				self.selection = {nil, nil}
				// 			} else {
				// 				if time._nsec <=
				// 				   (t.datetime_to_time(dt.DateTime{self.selection[0].?, {}}) or_else t.Time{})._nsec {
				// 					self.selection[0] = date
				// 				} else {
				// 					self.selection[1] = date
				// 				}
				// 			}
				// 		}
				// 	} else {
				// 		self.selection[0] = date
				// 	}
				// 	self.month_offset = 0
				// }
			}
		}
	}
}

Calendar_Day :: struct {
	using object:  ^Object,
	day:           int,
	is_today:      bool,
	is_this_month: bool,
	time:          t.Time,
	selection:     [2]t.Time,
	focus_time:    f32,
}

calendar_day :: proc(
	day: int,
	is_today: bool,
	is_this_month: bool,
	time: t.Time,
	selection: [2]t.Time,
	focus_time: f32,
) {
	object := persistent_object(hash(day + 1))
	if object.variant == nil {
		object.variant = Calendar_Day {
			object = object,
		}
	}

	self := &object.variant.(Calendar_Day)
	self.day = day
	self.is_today = is_today
	self.is_this_month = is_this_month
	self.selection = selection
	self.placement = next_user_placement()
	if begin_object(object) {
		end_object()
	}
}

display_calendar_day :: proc(self: ^Calendar_Day) {
	if point_in_box(mouse_point(), self.box) {
		hover_object(self)
	}
	handle_object_click(self)
	if object_is_visible(self) {
		if self.time._nsec > self.selection[0]._nsec &&
		   self.time._nsec <= self.selection[1]._nsec + i64(t.Hour * 24) {
			corners: [4]f32
			if self.time._nsec == self.selection[0]._nsec + i64(t.Hour * 24) {
				corners[0] = global_state.style.rounding
				corners[2] = global_state.style.rounding
			}
			if self.time._nsec == self.selection[1]._nsec + i64(t.Hour * 24) {
				corners[1] = global_state.style.rounding
				corners[3] = global_state.style.rounding
			}
			vgo.fill_box(
				self.box,
				corners,
				vgo.fade(
					global_state.style.color.substance,
					1 if self.is_this_month else 0.5,
				),
			)
		} else {
			if .Hovered in self.state.current {
				vgo.fill_box(
					self.box,
					global_state.style.shape.rounding,
					paint = global_state.style.color.substance,
				)
			} else if self.is_today {
				vgo.stroke_box(
					self.box,
					1,
					global_state.style.shape.rounding,
					paint = global_state.style.color.substance,
				)
			}
		}
		if self.focus_time > 0 {
			vgo.fill_box(
				self.box,
				global_state.style.shape.rounding,
				vgo.fade(global_state.style.color.content, self.focus_time),
			)
		}
		vgo.fill_text(
			fmt.tprint(self.day),
			global_state.style.default_text_size,
			box_center(self.box),
			font = global_state.style.default_font,
			align = 0.5,
			paint = vgo.mix(
				self.focus_time,
				global_state.style.color.content if self.is_this_month else vgo.fade(global_state.style.color.content, 0.5),
				global_state.style.color.field,
			),
		)
	}
}

Date_Picker :: struct {
	using object:  ^Object,
	first, second: ^Maybe(Date),
}

date_picker :: proc(first, second: ^Maybe(Date), loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Date_Picker {
				object = object,
			}
		}
		self := &object.variant.(Date_Picker)
		// init_input(info, loc) or_return
		// if self.builder == nil {
		// 	self.builder = &self.self.input.builder
		// }
		// if first, ok := self.first.?; ok {
		// 	self.text = fmt.tprintf("%2i/%2i/%4i", first.month, first.day, first.year)
		// }
		// if .Active in (self.self.state - self.self.last_state) {
		// 	strings.builder_reset(self.builder)
		// 	strings.write_string(self.builder, self.text)
		// }
		// self.monospace = true
	}
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

display_date_picker :: proc(self: ^Date_Picker) {
	if .Open in self.state.previous {
		if begin_layer(options = {.Attached}, kind = .Background) {
			defer end_layer()

			if begin_layout(
				placement = Future_Box_Placement {
					origin = {
						self.box.hi.x + global_state.style.popup_margin,
						box_center_y(self.box),
					},
					align = {0, 0.5},
				},
				padding = 10,
				clip_contents = true,
			) {
				defer end_layout()

				foreground()
				set_width(nil)
				set_height(nil)
				calendar(date = self.first, until = self.second)

				if (current_layer().?.state & {.Hovered, .Focused} == {}) &&
				   (.Focused not_in self.state.current) {
					self.state.current -= {.Open}
				}
			}
		}
	} else {
		if .Pressed in new_state(self.state) {
			self.state.current += {.Open}
		}
	}
}
