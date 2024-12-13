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
	month_offset:    int,
	focus_time:      f32,
}

todays_date :: proc() -> Date {
	year, month, day := t.date(t.now())
	return Date{i64(year), i8(month), i8(day)}
}

dates_are_equal :: proc(a, b: Date) -> bool {
	return a.year == b.year && a.month == b.month && a.day == b.day
}

DAYS_PER_WEEK :: 7
MONTHS_PER_YEAR :: 12
HOURS_PER_DAY :: 24

resolve_month_overflow :: proc(month, year: int) -> (int, int) {
	modifier := month - 1
	modifier -= 11 * int(month < 1)
	modifier /= MONTHS_PER_YEAR
	return month - MONTHS_PER_YEAR * modifier, year + modifier
}

calendar :: proc(date: ^Maybe(Date), until: ^Maybe(Date) = nil, loc := #caller_location) {
	assert(date != nil, loc = loc)
	object := persistent_object(hash(loc))

	if object.variant == nil {
		object.variant = Calendar {
			object = object,
		}
	}
	self := &object.variant.(Calendar)
	self.metrics.desired_size = {280, 0}
	row_height := self.metrics.desired_size.x / DAYS_PER_WEEK
	self.metrics.desired_size.y = row_height * 2

	viewed_date := date.? or_else todays_date()

	from_date := date^
	to_date := until^ if until != nil else Maybe(Date)(nil)

	month := int(viewed_date.month) + self.month_offset
	year := int(viewed_date.year)

	month, year = resolve_month_overflow(month, year)

	selection_times := [2]t.Time{
		t.datetime_to_time(dt.DateTime{from_date.? or_else Date{}, {}}) or_else t.Time{},
		t.datetime_to_time(dt.DateTime{to_date.? or_else (from_date.? or_else Date{}), {}}) or_else t.Time{},
	}

	month_start := t.datetime_to_time(i64(year), i8(month), 1, 0, 0, 0) or_else t.Time{}

	weekday := t.weekday(month_start)
	calendar_start := month_start._nsec - i64(weekday) * i64(t.Hour * HOURS_PER_DAY)

	day_count := 0
	if days_in_month, err := dt.last_day_of_month(i64(year), i8(month)); err == nil {
		day_count = int(days_in_month)
	}

	day_count = int(
		(month_start._nsec - calendar_start) / i64(t.Hour * HOURS_PER_DAY) + i64(day_count),
	)
	day_count = int(math.ceil(f32(day_count) / DAYS_PER_WEEK)) * DAYS_PER_WEEK
	weeks := math.ceil(f32(day_count) / DAYS_PER_WEEK)
	self.metrics.desired_size.y += weeks * row_height + (weeks + 1) * CALENDAR_WEEK_SPACING
	self.content.side = .Top
	self.content.padding = 10
	self.placement = next_user_placement()
	self.focus_time = animate(self.focus_time, 0.2, date^ != nil)
	allow_range := until != nil

	if begin_object(self) {
		defer end_object()

		push_id(self.id)
		defer pop_id()

		push_placement_options()
		defer pop_placement_options()

		set_margin(bottom = 4)

		if begin_row_layout(size = Percent_Of_Width(14.28), justify = .Equal_Space) {
			defer end_layout()
			set_margin(bottom = 0)

			set_align(.Center)

			set_margin(left = 10)
			if button(text = "<<", style = .Ghost).clicked {
				self.month_offset -= 1
			}
			label(text = fmt.tprintf("%s %i", t.Month(month), year))
			set_margin(right = 10)
			if button(text = ">>", style = .Ghost).clicked {
				self.month_offset += 1
			}
		}

		set_width(Percent(14.28))

		if begin_row_layout(size = Percent_Of_Width(14.28), justify = .Equal_Space) {
			defer end_layout()
			set_margin(bottom = 0)

			set_height(Percent(100))
			WEEKDAY_ABBREVIATIONS :: [?]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
			for weekday in WEEKDAY_ABBREVIATIONS {
				label(text = weekday, align = 0.5, color = vgo.fade(colors().content, 0.5))
			}
		}

		set_height(Percent(100))

		if begin_row_layout(size = Percent_Of_Width(14.28)) {
			defer end_layout()

			set_margin(bottom = 0)

			time: t.Time = {calendar_start}
			for i in 0 ..< day_count {
				push_id(i + 1)
				defer pop_id()

				if (i > 0) && (i % 7 == 0) {
					end_layout()
					begin_row_layout(size = Percent_Of_Width(14.28))
				}

				year, _month, day := t.date(time)
				cell_date := Date{i64(year), i8(_month), i8(day)}
				time._nsec += i64(t.Hour * 24)

				today_year, today_month, today_day := t.date(t.now())

				if calendar_day(day, today_year == year && today_month == _month && today_day == day, month == int(_month), time, selection_times, self.focus_time).clicked {
					if allow_range {
						if from_date == nil {
							from_date = cell_date
						} else {
							if cell_date == from_date || cell_date == to_date {
								from_date, to_date = nil, nil
							} else {
								if time._nsec <=
								   (t.datetime_to_time(dt.DateTime{from_date.?, {}}) or_else t.Time{})._nsec {
									from_date = cell_date
								} else {
									to_date = cell_date
								}
							}
						}
					} else {
						from_date = cell_date if from_date == nil else nil
					}
					self.month_offset = 0
					date^ = from_date
					if until != nil {
						until^ = to_date
					}
				}
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
	loc := #caller_location,
) -> (
	result: Button_Result,
) {
	object := persistent_object(hash(loc))
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
		defer end_object()

		result = {
			clicked = .Clicked in self.state.previous,
			hovered = .Hovered in self.state.previous,
		}
	}
	return
}

display_calendar_day :: proc(self: ^Calendar_Day) {
	if point_in_box(mouse_point(), self.box) {
		hover_object(self)
	}
	handle_object_click(self)
	if .Hovered in self.state.current {
		set_cursor(.Pointing_Hand)
	}
	is_within_range := self.time._nsec > self.selection[0]._nsec &&
	   self.time._nsec <= self.selection[1]._nsec + i64(t.Hour * 24)
	is_first_day := self.selection[0]._nsec >= self.time._nsec && self.selection[0]._nsec <= self.time._nsec + i64(t.Hour * 24)
	is_last_day := self.selection[1]._nsec >= self.time._nsec && self.selection[1]._nsec <= self.time._nsec + i64(t.Hour * 24)
	self.focus_time = animate(self.focus_time, 0.2, is_first_day || is_last_day)
	if object_is_visible(self) {
		if is_within_range {
			corners: [4]f32
			if is_first_day {
				corners[0] = global_state.style.rounding
				corners[2] = global_state.style.rounding
			}
			if is_last_day {
				corners[1] = global_state.style.rounding
				corners[3] = global_state.style.rounding
			}
			vgo.fill_box(
				self.box,
				corners,
				vgo.fade(global_state.style.color.substance, 1 if self.is_this_month else 0.5),
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
