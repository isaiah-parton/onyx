package onyx

import "base:runtime"

import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:os"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import "tedit"

import ttf "vendor:stb/truetype"

FMT_BUFFER_COUNT :: 128
FMT_BUFFER_SIZE :: 1024
TEXT_BREAK :: "..."
FONT_SIZE_PRECISION :: 0.5
MAX_FONT_SIZE :: 144.0
FONT_SIZE_COUNT :: int(MAX_FONT_SIZE / FONT_SIZE_PRECISION)

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

Text_Wrap :: enum {
	None,
	Normal,
	Word,
}

Text_Info :: struct {
	using options: Text_Options,
	text:          string,
}

Text_Options :: struct {
	font:      int,
	size:      f32,
	width:     Maybe(f32),
	max_lines: Maybe(int),
	wrap:      Text_Wrap,
	align_h:   Horizontal_Text_Align,
	align_v:   Vertical_Text_Align,
	hidden:    bool,
}

Interactive_Text_Result :: struct {
	changed, hovered: bool,
	bounds:           Box,
}

Text_Iterator :: struct {
	info:                         Text_Info,
	font:                         ^Font,
	size:                         ^Font_Size,
	glyph:                        Glyph,
	line_limit:                   Maybe(f32),
	line_size:                    [2]f32,
	new_line:                     bool, // Set if `codepoint` is the first rune on a new line
	glyph_pos:                    [2]f32,
	last_codepoint, codepoint:    rune,
	next_word, index, next_index: int,
}

Font_Size :: struct {
	ascent:     f32,
	descent:    f32,
	line_gap:   f32,
	scale:      f32,
	glyphs:     []Maybe(Glyph),
	break_size: f32,
}

Font :: struct {
	name:      string,
	data:      ttf.fontinfo,
	sizes:     [FONT_SIZE_COUNT]Maybe(Font_Size),
	spacing:   f32,
	monospace: bool,
}

Glyph :: struct {
	source:  Box,
	offset:  [2]f32,
	advance: f32,
	vertices: []ttf.vertex,
}

Text_Job_Glyph :: struct {
	using glyph: Glyph,
	codepoint:   rune,
	pos:         [2]f32,
}

Text_Job_Line :: struct {
	offset, length: int,
	highlight:      [2]f32,
}

Text_Job :: struct {
	glyphs:                                   []Text_Job_Glyph,
	lines:                                    []Text_Job_Line,
	line_height:                              f32,
	size:                                     [2]f32,
	ascent:                                   f32,
	cursor_glyph, hovered_line, hovered_rune: int,
}

make_text_job :: proc(
	info: Text_Info,
	e: ^tedit.Editor = nil,
	mouse_pos: [2]f32 = {},
) -> (
	job: Text_Job,
	ok: bool,
) {
	iter := make_text_iterator(info) or_return

	// Check glyph limit
	if len(core.glyphs) > 4096 {
		clear(&core.glyphs)
	}

	first_glyph := len(core.glyphs)
	first_line := len(core.lines)

	line: Text_Job_Line = {
		offset    = 0,
		highlight = {math.F32_MAX, 0},
	}

	job.cursor_glyph = -1
	job.hovered_rune = -1

	hovered_rune: int = -1
	closest: f32 = math.F32_MAX

	job.ascent = iter.size.ascent

	job.line_height = iter.size.ascent - iter.size.descent + iter.size.line_gap
	job.hovered_line = max(0, int(mouse_pos.y / job.line_height))

	at_end: bool

	for {
		if !iterate_text(&iter) {
			at_end = true
		}

		// Add a glyph
		append(
			&core.glyphs,
			Text_Job_Glyph{glyph = iter.glyph, codepoint = iter.codepoint, pos = iter.glyph_pos},
		)

		// Figure out highlighting and cursor pos
		if e != nil {
			if e.selection[0] == iter.index {
				job.cursor_glyph = (len(core.glyphs) - first_glyph) - 1
			}
			lo, hi := min(e.selection[0], e.selection[1]), max(e.selection[0], e.selection[1])
			if lo <= iter.index && iter.index <= hi {
				line.highlight[0] = min(line.highlight[0], iter.glyph_pos.x)
				line.highlight[1] = max(line.highlight[1], iter.glyph_pos.x)
			}
		}

		// Check for hovered index
		diff := abs(iter.glyph_pos.x - mouse_pos.x)
		if diff < closest {
			closest = diff
			hovered_rune = iter.index
		}

		// Push a new line
		if iter.codepoint == '\n' || at_end {
			current_line := len(core.lines) - first_line

			// Clamp hovered line index if this is the last one
			if at_end {
				job.hovered_line = min(job.hovered_line, current_line)
			}

			// Determine hovered rune
			if current_line == job.hovered_line {
				job.hovered_rune = hovered_rune
			}

			// Reset glyph search
			hovered_rune = -1
			closest = math.F32_MAX

			// Determine line length in runes
			line.length = len(core.glyphs) - (line.offset + first_glyph)

			// Take slice of global glyphs
			glyphs := core.glyphs[first_glyph + line.offset:][:line.length]

			// Apply horizontal alignment
			if iter.info.align_h == .Middle {
				for &glyph in glyphs {
					glyph.pos.x -= iter.line_size.x / 2
				}
			} else if iter.info.align_h == .Right {
				for &glyph in glyphs {
					glyph.pos.x -= iter.line_size.x
				}
			}

			// Append a new line
			append(&core.lines, line)

			// Reset the current line
			line = Text_Job_Line {
				offset    = len(core.glyphs) - first_glyph,
				highlight = {math.F32_MAX, 0},
			}

			// Update text size
			job.size.x = max(job.size.x, iter.line_size.x)
			job.size.y += iter.line_size.y
		}

		if at_end {
			break
		}
	}

	// Take a slice of the global arrays
	job.glyphs = core.glyphs[first_glyph:]
	job.lines = core.lines[first_line:]

	// Apply vertical alignment
	if iter.info.align_v == .Middle {
		for &glyph in job.glyphs {
			glyph.pos.y -= math.floor(job.size.y / 2)
		}
	} else if iter.info.align_v == .Bottom {
		for &glyph in job.glyphs {
			glyph.pos.y -= job.size.y
		}
	}

	// Figure out which line is hovered
	line_count := int(math.floor(job.size.y / job.line_height))
	job.hovered_line = int(mouse_pos.y / job.line_height)
	if job.hovered_line < 0 || job.hovered_line >= line_count {
		job.hovered_line = -1
	}

	// We okay
	ok = true

	return
}

draw_text_highlight :: proc(job: Text_Job, pos: [2]f32, color: Color) {
	for line, l in job.lines {
		if line.highlight[0] < line.highlight[1] {
			line_top: f32 = job.line_height * f32(l)
			draw_box_fill(
				{
					pos + {line.highlight[0] - 1, line_top},
					pos + {line.highlight[1] + 1, line_top + job.line_height},
				},
				color,
			)
		}
	}
}

draw_text_glyphs :: proc(job: Text_Job, pos: [2]f32, color: Color) {
	pos := linalg.floor(pos)
	for glyph in job.glyphs {
		if glyph.codepoint == 0 do continue
		glyph_pos := pos + glyph.pos + glyph.offset
		draw_glyph(
			glyph.source,
			{glyph_pos, glyph_pos + (glyph.source.hi - glyph.source.lo)},
			color,
		)
	}
}

draw_text_cursor :: proc(job: Text_Job, pos: [2]f32, color: Color) {
	if job.cursor_glyph == -1 || job.cursor_glyph >= len(job.glyphs) {
		return
	}
	glyph := job.glyphs[job.cursor_glyph]
	glyph_pos := pos + glyph.pos
	draw_box_fill({glyph_pos + {-1, -2}, glyph_pos + {1, job.line_height + 2}}, color)
}

destroy_font :: proc(font: ^Font) {
	for &size in font.sizes {
		if size != nil {
			destroy_font_size(&size.?)
		}
	}
	delete(font.name)
}

destroy_font_size :: proc(font_size: ^Font_Size) {
	delete(font_size.glyphs)
}

make_text_iterator :: proc(info: Text_Info) -> (iter: Text_Iterator, ok: bool) {
	if info.size <= 0 {
		return
	}
	iter.info = info

	iter.font, ok = &core.fonts[info.font].?
	if !ok do return
	iter.size, ok = get_font_size(iter.font, info.size)
	if !ok do return

	iter.line_limit = info.width
	iter.line_size.y = iter.size.ascent - iter.size.descent + iter.size.line_gap
	return
}

get_glyph_from_fallback_font :: proc(codepoint: rune, size: f32) -> (glyph: Glyph, ok: bool) {
	font, _ok := &core.fonts[core.style.icon_font].?
	if !_ok do return
	return get_glyph(font, get_font_size(font, size) or_return, codepoint)
}

iterate_text_rune :: proc(it: ^Text_Iterator) -> bool {
	it.last_codepoint = it.codepoint
	if it.next_index >= len(it.info.text) {
		return false
	}
	// Update index
	it.index = it.next_index
	// Decode next codepoint
	bytes: int
	it.codepoint, bytes = utf8.decode_rune(it.info.text[it.index:])
	// Update next index
	it.next_index += bytes
	// Get current glyph data
	if it.codepoint == '\n' || it.codepoint == '\r' {
		it.glyph = {}
	} else {
		r := '•' if it.info.hidden else it.codepoint
		ok: bool
		it.glyph, ok = get_glyph(it.font, it.size, r)
		if !ok && r > unicode.MAX_LATIN1 {
			it.glyph, ok = get_glyph_from_fallback_font(r, it.info.size)
		}
	}
	return true
}

iterate_text :: proc(iter: ^Text_Iterator) -> (ok: bool) {

	// Update horizontal offset with last glyph
	if iter.codepoint != 0 {
		iter.glyph_pos.x += math.floor(iter.glyph.advance)
	}

	// Get the next glyph
	ok = iterate_text_rune(iter)

	if ok && iter.last_codepoint != 0 {
		iter.glyph_pos.x += iter.font.spacing
	}

	// Space needed to fit this glyph/word
	space: f32 = iter.glyph.advance
	if !ok {
		// We might need to use the end index
		iter.index = iter.next_index
		iter.codepoint = 0
		iter.glyph = {}
	} else {
		// Get the space for the next word if needed
		if (iter.info.wrap == .Word) &&
		   (iter.next_index >= iter.next_word) &&
		   (iter.codepoint != ' ') {
			for i := iter.next_word; true;  /**/{
				c, b := utf8.decode_rune(iter.info.text[i:])
				if c != '\n' {
					if g, ok := get_glyph(iter.font, iter.size, iter.codepoint); ok {
						space += g.advance
					}
				}
				if c == ' ' || i > len(iter.info.text) - 1 {
					iter.next_word = i + b
					break
				}
				i += b
			}
		}
	}

	// Reset new line state
	iter.new_line = false
	// If the last rune was '\n' then this is a new line
	if (iter.last_codepoint == '\n') {
		iter.new_line = true
	} else {
		// Or if this rune would exceede the limit
		if (iter.line_limit != nil && iter.line_size.x + space >= iter.line_limit.?) {
			if iter.info.wrap == .None {
				iter.index = iter.next_index
				iter.glyph_pos.y += iter.size.ascent - iter.size.descent
				ok = false
			} else {
				iter.new_line = true
			}
		}
	}

	// Update vertical offset if there's a new line or if reached end
	if iter.new_line {
		iter.line_size.x = 0
		iter.glyph_pos.x = 0
		#partial switch iter.info.align_h {
		case .Middle:
			iter.glyph_pos.x -= math.floor(measure_next_line(iter^) / 2)
		case .Right:
			iter.glyph_pos.x -= measure_next_line(iter^)
		}
		iter.glyph_pos.y += iter.size.ascent - iter.size.descent + iter.size.line_gap
	}
	iter.line_size.x += math.floor(iter.glyph.advance)
	if ok && iter.last_codepoint != 0 {
		iter.line_size.x += iter.font.spacing
	}

	return
}

measure_next_line :: proc(iter: Text_Iterator) -> f32 {
	iter := iter
	for iterate_text(&iter) {
		if iter.new_line {
			break
		}
	}
	return iter.line_size.x
}

measure_next_word :: proc(iter: Text_Iterator) -> (size: f32, end: int) {
	iter := iter
	for iterate_text_rune(&iter) {
		size += iter.glyph.advance + iter.font.spacing
		if iter.codepoint == ' ' {
			break
		}
	}
	end = iter.index
	return
}

measure_text :: proc(info: Text_Info) -> [2]f32 {
	job, _ := make_text_job(info)
	return job.size
}

load_font_from_file :: proc(path: string, monospace: bool = false) -> (handle: int, ok: bool) {
	data := os.read_entire_file(path) or_return
	defer delete(data)

	return load_font_from_memory(data, monospace)
}

load_font_from_memory :: proc(data: []u8, monospace: bool = false) -> (handle: int, ok: bool) {
	font := Font {
		spacing   = 0 if monospace else 1,
		monospace = monospace,
	}

	ttf.InitFont(&font.data, raw_data(data), 0) or_return

	for i in 0 ..< MAX_FONTS {
		if core.fonts[i] == nil {
			core.fonts[i] = font
			handle = int(i)
			ok = true
			break
		}
	}

	return
}

unload_font :: proc(handle: int) {
	if font, ok := &core.fonts[handle].?; ok {
		destroy_font(font)
		core.fonts[handle] = nil
	}
}

get_font_size :: proc(font: ^Font, size: f32) -> (data: ^Font_Size, ok: bool) {
	size := math.floor(size / FONT_SIZE_PRECISION) * FONT_SIZE_PRECISION
	index := clamp(int(size / FONT_SIZE_PRECISION), 0, FONT_SIZE_COUNT)
	data, ok = &font.sizes[index].?
	if !ok {
		scale := ttf.ScaleForPixelHeight(&font.data, size)
		// Compute vertical metrics
		ascent, descent, line_gap: i32
		ttf.GetFontVMetrics(&font.data, &ascent, &descent, &line_gap)
		// Define new font size
		font.sizes[index] = Font_Size{
			scale = scale,
			ascent = f32(ascent) * scale,
			descent = f32(descent) * scale,
			line_gap = f32(line_gap) * scale,
			glyphs = make([]Maybe(Glyph), font.data.numGlyphs),
		}
		data = &font.sizes[index].?
		ok = true
	}
	return
}

// First creates the glyph if it doesn't exist, then returns its data
get_glyph :: proc(font: ^Font, size: ^Font_Size, r: rune) -> (glyph: Glyph, ok: bool) {
	// Try fetching from map
	index := ttf.FindGlyphIndex(&font.data, r)
	if index == 0 {
		return
	}
	glyph, ok = size.glyphs[index].?
	// If the glyph doesn't exist, we create and render it
	if !ok {
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
		// vertices: [^]ttf.vertex
		// vertex_count := ttf.GetGlyphShape(&font.data, index, &vertices)
		// Set glyph data
		glyph = Glyph {
			source  = add_glyph_to_atlas(
				image_data,
				int(image_width),
				int(image_height),
				&core.atlas,
				&core.gfx,
			),
			// vertices = vertices[:vertex_count],
			offset  = {f32(glyph_offset_x), f32(glyph_offset_y) + size.ascent},
			advance = f32(advance),
		}
		if !font.monospace {
			glyph.advance -= f32(left_side_bearing)
		}
		glyph.advance *= size.scale
		// Assign the new glyph
		size.glyphs[index] = glyph
		ok = true
	}
	return
}

draw_text :: proc(origin: [2]f32, info: Text_Info, color: Color) -> [2]f32 {
	if job, ok := make_text_job(info); ok {
		draw_text_glyphs(job, origin, color)
		return job.size
	}
	return {}
}

draw_glyph_shape :: proc(glyph: Glyph, pos: [2]f32, scale: f32, color: Color) {
	path_begin()
	for v in glyph.vertices {
		switch v.type {
		case 1:
			path_move_to(pos + {f32(v.x), -f32(v.y)} * scale)
		case 2:
			path_line_to(pos + {f32(v.x), -f32(v.y)} * scale)
		case 3:
			path_quad_to(pos + {f32(v.cx), -f32(v.cy)} * scale, pos + {f32(v.x), -f32(v.y)} * scale)
		}
	}
	path_fill(color)
}

draw_aligned_rune :: proc(
	font: int,
	font_size: f32,
	icon: rune,
	origin: [2]f32,
	color: Color,
	align_h: Horizontal_Text_Align,
	align_v: Vertical_Text_Align,
) -> (
	size: [2]f32,
	ok: bool,
) #optional_ok {
	font := &core.fonts[font].?
	glyph := get_glyph(font, get_font_size(font, font_size) or_return, rune(icon)) or_return
	size = glyph.source.hi - glyph.source.lo

	box: Box
	switch align_h {
	case .Right:
		box.lo.x = origin.x - size.x
		box.hi.x = origin.x
	case .Middle:
		box.lo.x = origin.x - size.x / 2
		box.hi.x = origin.x + size.x / 2
	case .Left:
		box.lo.x = origin.x
		box.hi.x = origin.x + size.x
	}
	switch align_v {
	case .Bottom, .Baseline:
		box.lo.y = origin.y - size.y
		box.hi.y = origin.y
	case .Middle:
		box.lo.y = origin.y - size.y / 2
		box.hi.y = origin.y + size.y / 2
	case .Top:
		box.lo.y = origin.y
		box.hi.y = origin.y + size.y
	}

	draw_glyph(glyph.source, box, color)
	return
}
