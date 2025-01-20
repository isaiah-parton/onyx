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
DAYS_PER_WEEK :: 7
MONTHS_PER_YEAR :: 12
HOURS_PER_DAY :: 24

Calendar_Page :: struct {
	year:  i64,
	month: i8,
}

Calendar :: struct {
	using object: ^Object,
	page:         Maybe(Calendar_Page),
	focus_time:   f32,
}

move_calendar_page :: proc(page: Calendar_Page, months: i8) -> Calendar_Page {
	page := page
	page.month += months
	modifier := page.month - 1
	modifier -= 11 * i8(page.month < 1)
	modifier /= MONTHS_PER_YEAR
	return {month = page.month - MONTHS_PER_YEAR * modifier, year = page.year + i64(modifier)}
}

todays_calendar_page :: proc() -> Calendar_Page {
	date := todays_date()
	return {month = date.month, year = date.year}
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

	if object.variant == nil {
		object.variant = Calendar {
			object = object,
		}
		object.state.input_mask = OBJECT_STATE_ALL
	}
	extras := &object.variant.(Calendar)

	object.size = {280, 0}
	row_height := object.size.x / DAYS_PER_WEEK
	object.size.y = row_height * 2

	page := extras.page.? or_else todays_calendar_page()
	if extras.page == nil {
		extras.page = page
	}

	from_date := date^
	to_date := until^ if until != nil else Maybe(Date)(nil)

	selection_times := [2]t.Time {
		t.datetime_to_time(dt.DateTime{from_date.? or_else Date{}, {}}) or_else t.Time{},
		t.datetime_to_time(
			dt.DateTime{to_date.? or_else (from_date.? or_else Date{}), {}},
		) or_else t.Time{},
	}

	month_start := t.datetime_to_time(page.year, page.month, 1, 0, 0, 0) or_else t.Time{}

	weekday := t.weekday(month_start)
	calendar_start := month_start._nsec - i64(weekday) * i64(t.Hour * HOURS_PER_DAY)

	how_many_days := 0
	if days_in_month, err := dt.last_day_of_month(page.year, page.month); err == nil {
		how_many_days = int(days_in_month)
	}

	how_many_days = int(
		(month_start._nsec - calendar_start) / i64(t.Hour * HOURS_PER_DAY) + i64(how_many_days),
	)
	how_many_days = int(math.ceil(f32(how_many_days) / DAYS_PER_WEEK)) * DAYS_PER_WEEK
	how_many_weeks := math.ceil(f32(how_many_days) / DAYS_PER_WEEK)
	object.size.y +=
		how_many_weeks * row_height + (how_many_weeks + 1) * CALENDAR_WEEK_SPACING
	extras.focus_time = animate(extras.focus_time, 0.2, date^ != nil)
	allow_range := until != nil

	if begin_object(object) {
		defer end_object()

		push_id(object.id)
		defer pop_id()

		if begin_layout(side = .Left) {
			defer end_layout()

			if button(text = "<<", accent = .Subtle).clicked {
				extras.page = move_calendar_page(page, -1)
			}
			label(text = fmt.tprintf("%s %i", t.Month(page.month), page.year))
			if button(text = ">>", accent = .Subtle).clicked {
				extras.page = move_calendar_page(page, 1)
			}
		}

		set_height(remaining_space().y * 0.1428)

		if begin_layout(side = .Left) {
			defer end_layout()

			set_width(remaining_space().x)
			WEEKDAY_ABBREVIATIONS :: [?]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
			for weekday in WEEKDAY_ABBREVIATIONS {
				label(text = weekday, align = 0.5, color = vgo.fade(style().color.content, 0.5))
			}
		}

		set_height(remaining_space().y)

		if begin_layout(side = .Left) {
			defer end_layout()

			time: t.Time = {calendar_start}
			for i in 0 ..< how_many_days {
				push_id(int(time._nsec))
				defer pop_id()

				if (i > 0) && (i % 7 == 0) {
					end_layout()
					begin_layout(side = .Left)
				}

				year, month, day := t.date(time)
				cell_date := Date{i64(year), i8(month), i8(day)}
				cell_year, cell_month, cell_day := t.date(t.now())

				if calendar_day(day, cell_year == year && cell_month == month && cell_day == day, page.month == i8(month), time, selection_times, extras.focus_time).clicked {
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
						if cell_date == from_date {
							from_date = nil
						} else {
							from_date = cell_date
						}
					}
					date^ = from_date
					if until != nil {
						until^ = to_date
					}
				}

				time._nsec += i64(t.Hour * 24)
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
	self.time = time
	self.selection = selection
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
	is_within_range :=
		self.time._nsec >= self.selection[0]._nsec && self.time._nsec <= self.selection[1]._nsec
	is_first_day := self.selection[0]._nsec == self.time._nsec
	is_last_day := self.selection[1]._nsec == self.time._nsec
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
				vgo.fade(style().color.button, 1 if self.is_this_month else 0.5),
			)
		} else {
			if .Hovered in self.state.current {
				vgo.fill_box(
					self.box,
					global_state.style.shape.rounding,
					paint = style().color.button,
				)
			} else if self.is_today {
				vgo.stroke_box(
					self.box,
					1,
					global_state.style.shape.rounding,
					paint = style().color.button,
				)
			}
		}
		if self.focus_time > 0 {
			vgo.fill_box(
				self.box,
				global_state.style.shape.rounding,
				vgo.fade(style().color.content, self.focus_time),
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
				style().color.content if self.is_this_month else vgo.fade(style().color.content, 0.5),
				style().color.field,
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
