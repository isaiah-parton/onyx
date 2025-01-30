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
	range:        [2]dt.Ordinal,
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

calendar :: proc(from: ^Maybe(Date), to: ^Maybe(Date) = nil, loc := #caller_location) {
	if from == nil {
		return
	}
	object := persistent_object(hash(loc))

	if object.variant == nil {
		object.variant = Calendar {
			object = object,
		}
		object.state.input_mask = OBJECT_STATE_ALL
	}
	extras := &object.variant.(Calendar)

	object.size = {234, 0}
	row_height := object.size.x / DAYS_PER_WEEK
	header_height := f32(30)
	object.size.y = row_height + header_height

	page := extras.page.? or_else todays_calendar_page()
	if extras.page == nil {
		extras.page = page
	}

	from_date := from^
	to_date := to^ if to != nil else Maybe(Date)(nil)

	from_ordinal := dt.date_to_ordinal(from_date.? or_else dt.Date{}) or_else 0
	to_ordinal := dt.date_to_ordinal(to_date.? or_else dt.Date{}) or_else from_ordinal
	today_ordinal, _ := dt.date_to_ordinal(todays_date())

	page_date := dt.Date{i64(page.year), i8(page.month), i8(1)}

	ordinal, _ := dt.date_to_ordinal(page_date)
	ordinal_day_of_week := dt.day_of_week(ordinal)
	ordinal -= i64(ordinal_day_of_week)

	how_many_days := 0
	if days_in_month, err := dt.last_day_of_month(page.year, page.month); err == nil {
		how_many_days = int(days_in_month)
	}
	how_many_days += int(ordinal_day_of_week)

	how_many_weeks := int(math.ceil(f32(how_many_days) / DAYS_PER_WEEK))

	how_many_days = how_many_weeks * DAYS_PER_WEEK

	object.size.y += f32(how_many_weeks) * row_height + f32(how_many_weeks) * CALENDAR_WEEK_SPACING

	extras.focus_time = animate(extras.focus_time, 0.2, from^ != nil)

	allow_range := to != nil

	object.box = next_box(object.size)
	object.state.input_mask = {}
	object.flags += {.Sticky_Press, .Sticky_Hover}

	if begin_object(object) {
		defer end_object()

		set_next_box(object.box)
		begin_layout(.Top)
		defer end_layout()

		push_id(object.id)
		defer pop_id()

		set_width(remaining_space().x)
		set_height(header_height)

		if begin_layout(side = .Left) {
			defer end_layout()

			set_align(.Center)
			set_width(0)
			label(fmt.tprintf("%s %i", t.Month(page.month), page.year), align = 0.5)

			set_side(.Right)
			set_size_mode(.Fixed)
			set_width(remaining_space().y)
			if button(text = "\uE0F6", accent = .Subtle, font_size = 20, text_align = 0.5).clicked {
				extras.page = todays_calendar_page()
			}
			if button(text = "\uE126", accent = .Subtle, font_size = 20, text_align = 0.5).clicked {
				extras.page = move_calendar_page(page, 1)
			}
			if button(text = "\uE0fe", accent = .Subtle, font_size = 20, text_align = 0.5).clicked {
				extras.page = move_calendar_page(page, -1)
			}
		}

		set_height(row_height)
		if begin_layout(side = .Left) {
			defer end_layout()

			set_width(remaining_space().x / 7)
			WEEKDAY_ABBREVIATIONS :: [?]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
			for weekday in WEEKDAY_ABBREVIATIONS {
				label(text = weekday, align = 0.5, color = vgo.fade(style().color.content, 0.5))
			}
		}

		divider()

		space(CALENDAR_WEEK_SPACING)

		layout := current_layout().?
		calendar_box := layout.box
		row := clamp(int((mouse_point().y - calendar_box.lo.y) / (row_height + CALENDAR_WEEK_SPACING)), 0, how_many_weeks - 1)
		column := clamp(int((mouse_point().x - calendar_box.lo.x) / (remaining_space().x / 7)), 0, 6)

		if point_in_box(mouse_point(), calendar_box) {
			hover_object(object)
		}
		selected_ordinal := ordinal + i64(row) * 7 + i64(column)

		previous_range := extras.range
		if .Pressed in object.state.current {
			if .Pressed in object.state.previous {
				extras.range[1] = selected_ordinal
			} else {
				extras.range = selected_ordinal
			}
		}
		if previous_range != extras.range {
			object.state.current += {.Changed}
		}

		if begin_layout(side = .Left) {
			set_width(remaining_space().x / 7)
			defer end_layout()

			for i in 0 ..< how_many_days {
				if (i > 0) && (i % 7 == 0) {
					end_layout()
					space(CALENDAR_WEEK_SPACING)
					begin_layout(side = .Left)
					set_width(remaining_space().x / 7)
				}

				cell_year, cell_month, cell_day := t.date(t.now())
				ordinal_date := dt.ordinal_to_date(ordinal) or_continue

				box := next_box({})

				stroke_color := style().color.foreground_stroke
				if from_ordinal <= ordinal && ordinal <= to_ordinal {
					if from_ordinal < to_ordinal {
						vgo.fill_box(
							box,
							hstack_corner_radius(
								int(ordinal - from_ordinal),
								int(to_ordinal - from_ordinal) + 1,
							) *
							style().rounding,
							vgo.fade(style().color.accent, 0.5),
						)
					}
					if from_ordinal == ordinal || to_ordinal == ordinal {
						vgo.fill_box(
							shrink_box(box, 1),
							style().rounding,
							paint = style().color.accent,
						)
					}
					stroke_color = style().color.content
				} else {
					vgo.fill_box(
						box,
						style().rounding,
						paint = vgo.fade(
							style().color.button,
							0.5 * f32(i32(selected_ordinal == ordinal) & i32(.Hovered in object.state.current)),
						),
					)
				}
				if ordinal == today_ordinal {
					vgo.stroke_box(
						box,
						1,
						style().rounding,
						paint = stroke_color,
					)
				}
				vgo.fill_text(
					fmt.tprint(ordinal_date.day),
					style().default_text_size,
					box_center(box),
					style().default_font,
					0.5,
					paint = vgo.fade(
						style().color.content,
						max(
							0.5,
							f32(i32(from_ordinal <= ordinal) & i32(to_ordinal >= ordinal)),
							f32(i32(ordinal_date.month == page_date.month)),
						),
					),
				)
				ordinal += 1
			}
		}
	}

	if .Changed in object.state.current {
		if date, err := dt.ordinal_to_date(min(extras.range[0], extras.range[1])); err == .None {
			from^ = date
		}
		if to != nil {
			if date, err := dt.ordinal_to_date(max(extras.range[0], extras.range[1])); err == .None {
				to^ = date
			}
		}
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
