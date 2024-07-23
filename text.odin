package ui

import "core:runtime"
import "core:os"

import "core:c/libc"
import "core:math"
import "core:math/bits"
import "core:math/linalg"

import "core:fmt"

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import sapp "../sokol-odin/sokol/app"

import ttf "vendor:stb/truetype"

FMT_BUFFER_COUNT 		:: 24
FMT_BUFFER_SIZE 		:: 200
TEXT_BREAK :: "..."

Horizontal_Text_Align :: enum {
	Left,
	Middle,
	Right,
}
Vertical_Text_Align :: enum {
	Top,
	Middle,
	Baseline,
	Bottom,
}
/*
	Text editing
*/
Text_Selection :: union {
	Text_Selection_Index,
	Text_Selection_Range,
}
Text_Selection_Index :: struct {
	index,
	line,
	column: int,
}
Text_Selection_Range :: struct {
	start,
	end: int,
}
Text_Wrap :: enum {
	None,
	Regular,
	Word,
}
Text_Info :: struct {
	font: Font_Handle,
	size: f32,
	text: string,
	limit: [2]Maybe(f32),

	wrap: Text_Wrap,
	align_h: Horizontal_Text_Align,
	align_v: Vertical_Text_Align,
	hidden: bool,
}
Text_Iterator :: struct {
	font: ^Font,
	size: ^Font_Size,
	glyph: ^Glyph,
	line_limit: Maybe(f32),
	line_size: [2]f32,
	new_line: bool, // Set if `codepoint` is the first rune on a new line
	offset: [2]f32,

	last_codepoint,
	codepoint: rune,
	next_word,
	index,
	next_index: int,
}
Font_Handle :: int
Font_Size :: struct {
	ascent,
	descent,
	line_gap,
	scale: f32,
	glyphs: map[rune]Glyph,
	// Helpers
	break_size: f32,
}
destroy_font_size :: proc(using self: ^Font_Size) {
	for _, &glyph in glyphs {
		destroy_glyph_data(&glyph)
	}
	delete(glyphs)
}
Font :: struct {
	name,
	path: string,
	data: ttf.fontinfo,
	sizes: map[f32]Font_Size,
}
destroy_font :: proc(using self: ^Font) {
	for _, &size in sizes {
		destroy_font_size(&size)
	}
	delete(name)
	delete(path)
}
/*
	A rasterized glyph
*/
Glyph :: struct {
	image: Image,
	src: Box,
	offset: [2]f32,
	advance: f32,
}
destroy_glyph_data :: proc(using self: ^Glyph) {
	destroy_image(&image)
}

/*
	Text formatting for short term usage
	each string is valid until it's home buffer is reused
*/
@private fmt_buffers: [FMT_BUFFER_COUNT][FMT_BUFFER_SIZE]u8
@private fmt_buffer_index: u8

get_tmp_builder :: proc() -> strings.Builder {
	buf := get_tmp_buffer()
	return strings.builder_from_bytes(buf)
}
get_tmp_buffer :: proc() -> []u8 {
	defer	fmt_buffer_index = (fmt_buffer_index + 1) % FMT_BUFFER_COUNT
	return fmt_buffers[fmt_buffer_index][:]
}
tmp_print :: proc(args: ..any) -> string {
	str := fmt.bprint(fmt_buffers[fmt_buffer_index][:], ..args)
	fmt_buffer_index = (fmt_buffer_index + 1) % FMT_BUFFER_COUNT
	return str
}
tmp_printf :: proc(text: string, args: ..any) -> string {
	str := fmt.bprintf(fmt_buffers[fmt_buffer_index][:], text, ..args)
	fmt_buffer_index = (fmt_buffer_index + 1) % FMT_BUFFER_COUNT
	return str
}
tmp_join :: proc(args: []string, sep := " ") -> string {
	size := 0
	buffer := &fmt_buffers[fmt_buffer_index]
	for arg, index in args {
		copy(buffer[size:size + len(arg)], arg[:])
		size += len(arg)
		if index < len(args) - 1 {
			copy(buffer[size:size + len(sep)], sep[:])
			size += len(sep)
		}
	}
	str := string(buffer[:size])
	fmt_buffer_index = (fmt_buffer_index + 1) % FMT_BUFFER_COUNT
	return str
}
trim_zeroes :: proc(text: string) -> string {
	text := text
	for i := len(text) - 1; i >= 0; i -= 1 {
		if text[i] != '0' {
			if text[i] == '.' {
				text = text[:i]
			}
			break
		} else {
			text = text[:i]
		}
	}
	return text
}
tmp_print_bit_set :: proc(set: $S/bit_set[$E;$U], sep := " ") -> string {
	size := 0
	buffer := &fmt_buffers[fmt_buffer_index]
	count := 0
	max := card(set)
	for member in E {
		if member not_in set {
			continue
		}
		name := fprint(member)
		copy(buffer[size:size + len(name)], name[:])
		size += len(name)
		if count < max - 1 {
			copy(buffer[size:size + len(sep)], sep[:])
			size += len(sep)
		}
		count += 1
	}
	str := string(buffer[:size])
	fmt_buffer_index = (fmt_buffer_index + 1) % FMT_BUFFER_COUNT
	return str
}

make_text_iterator :: proc(info: Text_Info) -> (it: Text_Iterator, ok: bool) {
	if info.size <= 0 {
		return
	}
	it.font = &core.atlas.fonts[info.font].?
	it.size, ok = get_font_size(it.font, info.size)
	it.line_limit = info.limit.x
	it.line_size.y = it.size.ascent - it.size.descent + it.size.line_gap
	return
}
update_text_iterator_offset :: proc(it: ^Text_Iterator, info: Text_Info) {
	it.offset.x = 0
	#partial switch info.align_h {
		case .Middle: it.offset.x -= math.floor(measure_next_line(info, it^) / 2)
		case .Right: it.offset.x -= measure_next_line(info, it^)
	}
}
iterate_text_codepoint :: proc(it: ^Text_Iterator, info: Text_Info) -> bool {
	it.last_codepoint = it.codepoint
	if it.next_index >= len(info.text) {
		return false
	}
	// Update index
	it.index = it.next_index
	// Decode next codepoint
	bytes: int
	it.codepoint, bytes = utf8.decode_rune(info.text[it.index:])
	// Update next index
	it.next_index += bytes
	// Get current glyph data
	if it.codepoint != '\n' {
		if glyph, ok := __get_glyph(it.font, it.size, '•' if info.hidden else it.codepoint); ok {
			it.glyph = glyph
		}
	} else {
		it.glyph = nil
	}
	return true
}
iterate_text :: proc(it: ^Text_Iterator, info: Text_Info) -> (ok: bool) {
	// Update horizontal offset with last glyph
	if it.glyph != nil {
		it.offset.x += it.glyph.advance
	}
	/*
		Pre-paint
			Decode the next codepoint -> Update glyph data -> New line if needed
	*/
	ok = iterate_text_codepoint(it, info)
	// Space needed to fit this glyph/word
	space: f32 = it.glyph.advance if it.glyph != nil else 0
	if !ok {
		// We might need to use the end index
		it.index = it.next_index
		it.glyph = nil
		it.codepoint = 0
	} else {
		// Get the space for the next word if needed
		if (info.wrap == .Word) && (it.next_index >= it.next_word) && (it.codepoint != ' ') {
			for i := it.next_word; true; /**/ {
				c, b := utf8.decode_rune(info.text[i:])
				if c != '\n' {
					if g, ok := __get_glyph(it.font, it.size, it.codepoint); ok {
						space += g.advance
					}
				}
				if c == ' ' || i > len(info.text) - 1 {
					it.next_word = i + b
					break
				}
				i += b
			}
		}
	}
	// Reset new line state
	it.new_line = false
	if it.codepoint == '\t' {
		it.line_size.x += it.glyph.advance
	}
	// If the last rune was '\n' then this is a new line
	if (it.last_codepoint == '\n') {
		it.new_line = true
	} else {
		// Or if this rune would exceede the limit
		if ( it.line_limit != nil && it.line_size.x + space >= it.line_limit.? ) {
			if info.wrap == .None {
				it.index = it.next_index
				it.offset.y += it.size.ascent - it.size.descent
				ok = false
			} else {
				it.new_line = true
			}
		}
	}
	// Update vertical offset if there's a new line or if reached end
	if it.new_line {
		it.line_size.x = 0
		it.offset.y += it.size.ascent - it.size.descent + it.size.line_gap
	} else if it.glyph != nil {
		it.line_size.x += it.glyph.advance
	}
	return
}
/*
	Measures until the next line
*/
measure_next_line :: proc(info: Text_Info, it: Text_Iterator) -> f32 {
	it := it
	for iterate_text(&it, info) {
		if it.new_line {
			break
		}
	}
	return it.line_size.x
}
measure_next_word :: proc(info: Text_Info, it: Text_Iterator) -> (size: f32, end: int) {
	it := it
	for iterate_text_codepoint(&it, info) {
		if it.glyph != nil {
			size += it.glyph.advance
		}
		if it.codepoint == ' ' {
			break
		}
	}
	end = it.index
	return
}
measure_text :: proc(info: Text_Info) -> [2]f32 {
	size: [2]f32
	if it, ok := make_text_iterator(info); ok {
		for iterate_text(&it, info) {
			size.x = max(size.x, it.line_size.x)
			if it.new_line {
				size.y += it.size.ascent - it.size.descent + it.size.line_gap
			}
		}
		size.y += it.size.ascent - it.size.descent
	}
	return size
}
/*
	Load a font from a given file path
*/
load_font :: proc(file_path: string) -> (handle: Font_Handle, success: bool) {
	font: Font
	if file_data, ok := os.read_entire_file(file_path); ok {
		if ttf.InitFont(&font.data, raw_data(file_data), 0) {
			for i in 0..<MAX_FONTS {
				if core.atlas.fonts[i] == nil {
					core.atlas.fonts[i] = font
					handle = Font_Handle(i)
					success = true
					break
				}
			}
		} else {
			fmt.printf("[ui] Failed to initialize font '%s'\n", file_path)
		}
	} else {
		fmt.printf("[ui] Failed to load font '%s'\n", file_path)
	}
	return
}
/*
	Destroy a font and free it's handle
*/
unload_font :: proc(handle: Font_Handle) {
	if font, ok := &core.atlas.fonts[handle].?; ok {
		destroy_font(font)
		core.atlas.fonts[handle] = nil
	}
}
// Get the data for a given pixel size of the font
get_font_size :: proc(font: ^Font, size: f32) -> (data: ^Font_Size, ok: bool) {
	size := math.round(size)
	data, ok = &font.sizes[size]
	if !ok {
		data = map_insert(&font.sizes, size, Font_Size{})
		// Compute glyph scale
		data.scale = ttf.ScaleForPixelHeight(&font.data, f32(size))
		// Compute vertical metrics
		ascent, descent, line_gap: i32
		ttf.GetFontVMetrics(&font.data, &ascent, &descent, &line_gap)
		data.ascent = f32(f32(ascent) * data.scale)
		data.descent = f32(f32(descent) * data.scale)
		data.line_gap = f32(f32(line_gap) * data.scale)

		ok = true
	}
	return
}
// First creates the glyph if it doesn't exist, then returns its data
__get_glyph :: proc(font: ^Font, size: ^Font_Size, codepoint: rune) -> (data: ^Glyph, ok: bool) {
	// Try fetching from map
	data, ok = &size.glyphs[codepoint]
	// If the glyph doesn't exist, we create and render it
	if !ok {
		// Get codepoint index
		index := ttf.FindGlyphIndex(&font.data, codepoint)
		// Get metrics
		advance, left_side_bearing: i32
		ttf.GetGlyphHMetrics(&font.data, index, &advance, &left_side_bearing)
		// Generate bitmap
		image_width, image_height, glyph_offset_x, glyph_offset_y: libc.int
		image_data := ttf.GetGlyphBitmap(
			&font.data, 
			size.scale, 
			size.scale, 
			index,
			&image_width,
			&image_height,
			&glyph_offset_x,
			&glyph_offset_y,
		)
		image: Image 
		src: Box
		if image_data != nil {
			image = {
				data = transmute([]u8)runtime.Raw_Slice({data = image_data, len = int(image_width * image_height)}),
				channels = 1,
				width = int(image_width),
				height = int(image_height),
			}
			src = add_atlas_image(&core.atlas, image) or_else Box{}
		}
		// Set glyph data
		data = map_insert(&size.glyphs, codepoint, Glyph({
			image = image,
			src = src,
			offset = {f32(glyph_offset_x), f32(glyph_offset_y) + size.ascent},
			advance = f32((f32(advance) + f32(left_side_bearing)) * size.scale),
		}))
		ok = true
	}
	return
}

draw_text :: proc(origin: [2]f32, info: Text_Info, color: Color) -> [2]f32 {
	size: [2]f32 
	origin := origin
	if info.align_v != .Top {
		size = measure_text(info)
		#partial switch info.align_v {
			case .Middle: origin.y -= math.floor(size.y / 2) 
			case .Bottom: origin.y -= size.y
		}
	}
	if it, ok := make_text_iterator(info); ok {
		update_text_iterator_offset(&it, info)
		for iterate_text(&it, info) {
			// Reset offset if new line
			if it.new_line {
				update_text_iterator_offset(&it, info)
			}
			// Paint the glyph
			if it.codepoint != '\n' && it.codepoint != ' ' && it.glyph != nil {
				dst: Box = {low = origin + it.offset + it.glyph.offset}
				dst.high = dst.low + (it.glyph.src.high - it.glyph.src.low)
				// if clip, ok := info.clip.?; ok {
				// 	draw_clipped_textured_box(painter.texture, it.glyph.src, dst, clip, color)
				// } else {
				// 	draw_textured_box(painter.texture, it.glyph.src, dst, color)
				// }
				draw_texture(it.glyph.src, dst, color)
			}
			// Update size
			if it.new_line {
				size.x = max(size.x, it.line_size.x)
				size.y += it.line_size.y
			}
		}
		size.y += it.line_size.y
	}
	return size 
}

draw_aligned_rune :: proc(
	font: Font_Handle, 
	size: f32, 
	icon: rune, 
	origin: [2]f32, 
	color: Color, 
	align_h: Horizontal_Text_Align, 
	align_v: Vertical_Text_Align,
) -> [2]f32 {
	font := &core.atlas.fonts[font].?
	font_size, _ := get_font_size(font, size)
	glyph, _ := __get_glyph(font, font_size, rune(icon))
	icon_size := glyph.src.high - glyph.src.low

	box: Box
	switch align_h {
		case .Right: 
		box.low.x = origin.x - icon_size.x
		box.high.x = origin.x 
		case .Middle: 
		box.low.x = origin.x - math.floor(icon_size.x / 2) 
		box.high.x = origin.x + math.floor(icon_size.x / 2)
		case .Left: 
		box.low.x = origin.x 
		box.high.x = origin.x + icon_size.x 
	}
	switch align_v {
		case .Bottom, .Baseline: 
		box.low.y = origin.y - icon_size.y
		box.high.y = origin.y 
		case .Middle: 
		box.low.y = origin.y - math.floor(icon_size.y / 2) 
		box.high.y = origin.y + math.floor(icon_size.y / 2)
		case .Top: 
		box.low.y = origin.y 
		box.high.y = origin.y + icon_size.y 
	}
	draw_texture(glyph.src, box, color)
	return icon_size
}

draw_rune_aligned_clipped :: proc(font: Font_Handle, size: f32, icon: rune, origin: [2]f32, color: Color, align: [2]Alignment, clip: Box) -> [2]f32 {
	font := &core.atlas.fonts[font].?
	font_size, _ := get_font_size(font, size)
	glyph, _ := __get_glyph(font, font_size, rune(icon))
	icon_size := glyph.src.high - glyph.src.low

	box: Box
	switch align.x {
		case .Far: 
		box.low.x = origin.x - icon_size.x
		box.high.x = origin.x 
		case .Middle: 
		box.low.x = origin.x - icon_size.x / 2 
		box.high.x = origin.x + icon_size.x / 2
		case .Near: 
		box.low.x = origin.x 
		box.high.x = origin.x + icon_size.x 
	}
	switch align.y {
		case .Far: 
		box.low.y = origin.y - icon_size.y
		box.high.y = origin.y 
		case .Middle: 
		box.low.y = origin.y - icon_size.y / 2 
		box.high.y = origin.y + icon_size.y / 2
		case .Near: 
		box.low.y = origin.y 
		box.high.y = origin.y + icon_size.y 
	}
	draw_texture(glyph.src, box, color)
	return icon_size
}

Interactive_Text_Info :: struct {
	using base: Text_Info,
	focus_selects_all,
	read_only: bool,
}
Interactive_Text_Result :: struct {
	// If a selection or a change was made
	changed: bool,
	// If the text is hovered
	hovered: bool,
	// Text and selection bounds
	bounds,
	selection_bounds: Box,
	// New selection
	selection: Text_Selection,
}
/*
	Paint interactable text
*/
draw_interactive_text :: proc(widget: ^Widget, origin: [2]f32, info: Interactive_Text_Info, color: Color) {
	// Initial measurement
	size := measure_text(info)
	origin := origin
	// Prepare result
	using result: Interactive_Text_Result = {
		selection_bounds = {math.F32_MAX, {}},
		selection = core.text_selection,
	}
	// Layer to paint on
	surface := __get_draw_surface()
	// Apply baseline if needed
	#partial switch info.align_v {
		case .Middle: origin.y -= size.y / 2 
		case .Bottom: origin.y -= size.y
	}
	// Hovered index
	hover_index: int
	// Paint the text
	if it, ok := make_text_iterator(info); ok {
		// If we've reached the end
		at_end := false
		// Determine hovered line
		line_height := it.size.ascent - it.size.descent + it.size.line_gap
		line_count := int(math.floor(size.y / line_height))
		hovered_line := clamp(int((core.mouse_pos.y - origin.y) / line_height), 0, line_count - 1)
		// Current line and column
		line, column: int
		// Keep track of smallest distance to mouse
		min_dist: f32 = math.F32_MAX
		// Get line offset
		update_text_iterator_offset(&it, info)
		// Top left of this line
		line_origin := origin + it.offset
		// Horizontal bounds of the selection on the current line
		line_box_bounds: [2]f32 = {math.F32_MAX, 0}
		// Set bounds
		bounds.low = line_origin
		bounds.high = bounds.low
		// Start iteration
		for {
			// Iterate the iterator
			if !iterate_text(&it, info) {
				at_end = true
			}
			// Get hovered state
			if it.new_line {
				// Allows for highlighting the last glyph in a line
				if hovered_line == line {
					dist1 := math.abs((origin.x + it.offset.x) - core.mouse_pos.x)
					if dist1 < min_dist {
						min_dist = dist1
						hover_index = it.index
					}
				}
				// Check if the last line was hovered
				line_box: Box = {line_origin, line_origin + it.line_size}
				if point_in_box(core.mouse_pos, line_box) {
					hovered = true
				}
				update_text_iterator_offset(&it, info)
				line += 1
				column = 0
				line_origin = origin + it.offset
			}
			// Update hovered index
			if hovered_line == line {
				// Left side of glyph
				dist1 := math.abs((origin.x + it.offset.x) - core.mouse_pos.x)
				if dist1 < min_dist {
					min_dist = dist1
					hover_index = it.index
				}
				if it.glyph != nil && (it.new_line || it.next_index >= len(info.text)) {
					// Right side of glyph
					dist2 := math.abs((origin.x + it.offset.x + it.glyph.advance) - core.mouse_pos.x)
					if dist2 < min_dist {
						min_dist = dist2
						hover_index = it.next_index
					}
				}
			}
			// Get the glyph point
			point: [2]f32 = origin + it.offset
			glyph_color := color
			// Get selection info
			if .Focused in (widget.state) {
				switch &selection in core.text_selection {
					case Text_Selection_Index:
					if selection.index == it.index {
						selection.line = line
						selection.column = column
						glyph_color = core.style.color.content
					}
					case Text_Selection_Range:
					if it.index >= selection.start && it.index <= selection.end {
						line_box_bounds = {
							min(line_box_bounds[0], point.x),
							max(line_box_bounds[1], point.x),
						}
						glyph_color = core.style.color.content
					}
				}
			}
			// Paint the glyph
			if it.glyph != nil {
				// Paint the glyph
				dst: Box = {low = point + it.glyph.offset}
				dst.high = dst.low + (it.glyph.src.high - it.glyph.src.low)
				bounds.high = linalg.max(bounds.high, dst.high)
				draw_texture(it.glyph.src, dst, glyph_color)
			}
			// Paint this line's selection
			if (.Focused in widget.state) && (it.index >= len(info.text) || info.text[it.index] == '\n') {
				// Draw it if the selection is valid
				if line_box_bounds[1] >= line_box_bounds[0] {
					box: Box = {
						{line_box_bounds[0] - 1, line_origin.y},
						{line_box_bounds[1] + 1, line_origin.y + it.line_size.y},
					}
					selection_bounds = {
						linalg.min(selection_bounds.low, box.low),
						linalg.max(selection_bounds.high, box.high),
					}
					draw_box_fill(box, core.style.color.accent)
					line_box_bounds = {math.F32_MAX, 0}
				}
			}
			// Break if reached end
			if at_end {
				break
			}
			// Increment column
			column += 1
		}
	}
	
	// These require `hover_index` to be determined
	if selection, ok := core.text_selection.(Text_Selection_Range); ok {
		if .Focused in widget.state {
			if (key_pressed(.C) && (key_down(.LEFT_CONTROL) || key_down(.RIGHT_CONTROL))) {
				set_clipboard_string(info.text[selection.start:selection.end])
			}
		}
	}
	/*// Update selection
	if .Pressed in (widget.state - widget.last_state) {
		if widget.click_count == 3 {
			// Select everything
			selection.offset = strings.last_index_byte(info.text[:hover_index], '\n') + 1
			ui.scribe.anchor = selection.offset
			selection.length = strings.index_byte(info.text[ui.scribe.anchor:], '\n')
			if selection.length == -1 {
				selection.length = len(info.text) - selection.offset
			}
		} else {
			// Normal select
			selection.offset = hover_index
			ui.scribe.anchor = hover_index
			selection.length = 0
		}
	}
	// Dragging
	if (.Pressed in widget.state) && (widget.click_count < 3) {
		// Selection by dragging
		if widget.click_count == 2 {
			next, last: int
			if hover_index < ui.scribe.anchor {
				last = hover_index if info.text[hover_index] == ' ' else max(0, strings.last_index_any(info.text[:hover_index], " \n") + 1)
				next = strings.index_any(info.text[ui.scribe.anchor:], " \n")
				if next == -1 {
					next = len(info.text) - ui.scribe.anchor
				}
				next += ui.scribe.anchor
			} else {
				last = max(0, strings.last_index_any(info.text[:ui.scribe.anchor], " \n") + 1)
				next = 0 if (hover_index > 0 && info.text[hover_index - 1] == ' ') else strings.index_any(info.text[hover_index:], " \n")
				if next == -1 {
					next = len(info.text) - hover_index
				}
				next += hover_index
			}
			selection.offset = last
			selection.length = next - last
		} else {
			if hover_index < ui.scribe.anchor {
				selection.offset = hover_index
				selection.length = ui.scribe.anchor - hover_index
			} else {
				selection.offset = ui.scribe.anchor
				selection.length = hover_index - ui.scribe.anchor
			}
		}
	}*/
	return
}

/*draw_text_box :: proc(info: Text_Box_Info, loc := #caller_location) -> Text_Box_Result {
	self, generic_result := get_widget(info, loc)
	result: Text_Box_Result = {
		generic = generic_result,
	}
	self.box = next_box(ui)
	text_info := info.text_info.(Text_Info) or_else info.text_info.(Tactile_Text_Info).base
	origin: [2]f32
	switch text_info.align {
		case .Left: origin.x = self.box.low.x
		case .Middle: origin.x = (self.box.low.x + self.box.high.x) / 2
		case .Right: origin.x = self.box.high.x
	}
	switch text_info.baseline {
		case .Top: origin.y = self.box.low.y
		case .Middle: origin.y = (self.box.low.y + self.box.high.y) / 2
		case .Bottom: origin.y = self.box.high.y
	}
	color := info.color.? or_else ui.style.color.content
	switch text_info in info.text_info {
		case Tactile_Text_Info: paint_tactile_text(ui, self, origin, text_info, color)
		case Text_Info: paint_text(ui.origin, text_info, color)
	}
	return result
}*/