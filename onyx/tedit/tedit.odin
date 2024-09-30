package tedit

// Based on "code:text/edit"

import "core:fmt"
import "base:runtime"
import "core:time"
import "core:strings"
import "core:unicode/utf8"

MAX_UNDO :: 10

Command_Set :: distinct bit_set[Command; u32]

Command :: enum u32 {
	None,
	Undo,
	Redo,
	New_Line,    // multi-lines
	Cut,
	Copy,
	Paste,
	Select_All,
	Backspace,
	Delete,
	Delete_Word_Left,
	Delete_Word_Right,
	Left,
	Right,
	Up,          // multi-lines
	Down,        // multi-lines
	Word_Left,
	Word_Right,
	Start,
	End,
	Line_Start,
	Line_End,
	Select_Left,
	Select_Right,
	Select_Up,   // multi-lines
	Select_Down, // multi-lines
	Select_Word_Left,
	Select_Word_Right,
	Select_Start,
	Select_End,
	Select_Line_Start,
	Select_Line_End,
}

MULTILINE_COMMANDS :: Command_Set{.New_Line, .Up, .Down, .Select_Up, .Select_Down}
EDIT_COMMANDS :: Command_Set{.New_Line, .Delete, .Delete_Word_Left, .Delete_Word_Right, .Backspace, .Cut, .Paste, .Undo, .Redo}

Editor :: struct {
	selection: [2]int,
	anchor: int,

	line_start,
	line_end: int,

	builder: ^strings.Builder,

	up_index,
	down_index: int,

	action: Undo_Action,
	undo: [dynamic]Undo_Action,
	redo: [dynamic]Undo_Action,
	undo_text_allocator: runtime.Allocator,

	// Set these if you want cut/copy/paste functionality
	set_clipboard: proc(user_data: rawptr, text: string) -> (ok: bool),
	get_clipboard: proc(user_data: rawptr) -> (text: string, ok: bool),
	clipboard_user_data: rawptr,
}

Undo_Action :: struct {
	selection: [2]int,
	text: string,
}

Translation :: enum u32 {
	Start,
	End,
	Left,
	Right,
	Up,
	Down,
	Word_Left,
	Word_Right,
	Word_Start,
	Word_End,
	Soft_Line_Start,
	Soft_Line_End,
}

make_editor :: proc(e: ^Editor, undo_text_allocator, undo_state_allocator: runtime.Allocator) {
	// Used for allocating `Undo_State`
	e.undo_text_allocator = undo_text_allocator

	e.undo.allocator = undo_state_allocator
	e.redo.allocator = undo_state_allocator
}

destroy_editor :: proc(e: ^Editor) {
	undo_clear(e, &e.undo)
	undo_clear(e, &e.redo)
	delete(e.undo)
	delete(e.redo)
	e.builder = nil
}

// Call at the beginning of each frame
begin :: proc(e: ^Editor, id: u64, builder: ^strings.Builder) {
	assert(builder != nil)
	e.selection = {len(builder.buf), 0}
	e.builder = builder
	set_text(e, string(e.builder.buf[:]))
	undo_clear(e, &e.undo)
	undo_clear(e, &e.redo)
}

set_text :: proc(e: ^Editor, text: string) {
	strings.builder_reset(e.builder)
	strings.write_string(e.builder, text)
}

editor_undo :: proc(e: ^Editor, undo, redo: ^[dynamic]Undo_Action) {
	if len(undo) > 0 {
		item := pop(undo)
		append(redo, Undo_Action{
			selection = e.selection,
			text = strings.clone_from_bytes(e.builder.buf[:], e.undo_text_allocator),
		})
		e.selection = item.selection
		clear(&e.builder.buf)
		append(&e.builder.buf, item.text)
	}
}

undo_clear :: proc(e: ^Editor, undo: ^[dynamic]Undo_Action) {
	for len(undo) > 0 {
		item := pop(undo)
		delete(item.text, e.undo_text_allocator)
	}
}

input_text :: proc(e: ^Editor, text: string) {
	if len(text) == 0 {
		return
	}
	if has_selection(e) {
		selection_delete(e)
	}
	insert(e, e.selection[0], text)
	offset := e.selection[0] + len(text)
	e.selection = {offset, offset}
}

input_runes :: proc(e: ^Editor, text: []rune) {
	if len(text) == 0 {
		return
	}
	undo_clear(e, &e.redo)
	append(&e.undo, Undo_Action{
		selection = e.selection,
		text = strings.clone_from_bytes(e.builder.buf[:], e.undo_text_allocator),
	})
	if len(e.undo) > MAX_UNDO {
		pop_front(&e.undo)
	}
	if has_selection(e) {
		selection_delete(e)
	}
	offset := e.selection[0]
	for r in text {
		b, w := utf8.encode_rune(r)
		text := string(b[:w])
		insert(e, offset, text)
		offset += w
	}
	e.selection = {offset, offset}
}

insert :: proc(e: ^Editor, at: int, text: string) {
	inject_at(&e.builder.buf, at, text)
}

remove :: proc(e: ^Editor, lo, hi: int) {
	remove_range(&e.builder.buf, lo, hi)
}

has_selection :: proc(e: ^Editor) -> bool {
	return e.selection[0] != e.selection[1]
}

sorted_selection :: proc(e: ^Editor) -> (lo, hi: int) {
	lo = min(e.selection[0], e.selection[1])
	hi = max(e.selection[0], e.selection[1])
	lo = clamp(lo, 0, len(e.builder.buf))
	hi = clamp(hi, 0, len(e.builder.buf))
	e.selection[0] = lo
	e.selection[1] = hi
	return
}

selection_delete :: proc(e: ^Editor) {
	lo, hi := sorted_selection(e)
	remove(e, lo, hi)
	e.selection = {lo, lo}
}

translate_position :: proc(e: ^Editor, pos: int, t: Translation) -> int {
	is_continuation_byte :: proc(b: byte) -> bool {
		return b >= 0x80 && b < 0xc0
	}
	is_space :: proc(b: byte) -> bool {
		return b == ' ' || b == '\t' || b == '\n'
	}

	buf := e.builder.buf[:]

	pos := pos
	pos = clamp(pos, 0, len(buf))

	switch t {
	case .Start:
		pos = 0
	case .End:
		pos = len(buf)
	case .Left:
		pos -= 1
		for pos >= 0 && is_continuation_byte(buf[pos]) {
			pos -= 1
		}
	case .Right:
		pos += 1
		for pos < len(buf) && is_continuation_byte(buf[pos]) {
			pos += 1
		}
	case .Up:
		pos = e.up_index
	case .Down:
		pos = e.down_index
	case .Word_Left:
		for pos > 0 && is_space(buf[pos-1]) {
			pos -= 1
		}
		for pos > 0 && !is_space(buf[pos-1]) {
			pos -= 1
		}
	case .Word_Right:
		for pos < len(buf) && !is_space(buf[pos]) {
			pos += 1
		}
		for pos < len(buf) && is_space(buf[pos]) {
			pos += 1
		}
	case .Word_Start:
		for pos > 0 && !is_space(buf[pos-1]) {
			pos -= 1
		}
	case .Word_End:
		for pos < len(buf) && !is_space(buf[pos]) {
			pos += 1
		}
	case .Soft_Line_Start:
		pos = e.line_start
	case .Soft_Line_End:
		pos = e.line_end
	}
	return clamp(pos, 0, len(buf))
}

move_to :: proc(e: ^Editor, t: Translation) {
	if t == .Left && has_selection(e) {
		lo, _ := sorted_selection(e)
		e.selection = {lo, lo}
	} else if t == .Right && has_selection(e) {
		_, hi := sorted_selection(e)
		e.selection = {hi, hi}
	} else {
		pos := translate_position(e, e.selection[0], t)
		e.selection = {pos, pos}
	}
}

select_to :: proc(e: ^Editor, t: Translation) {
	e.selection[0] = translate_position(e, e.selection[0], t)
}

delete_to :: proc(e: ^Editor, t: Translation) {
	if has_selection(e) {
		selection_delete(e)
	} else {
		lo := e.selection[0]
		hi := translate_position(e, lo, t)
		lo, hi = min(lo, hi), max(lo, hi)
		remove(e, lo, hi)
		e.selection = {lo, lo}
	}
}

current_selected_text :: proc(e: ^Editor) -> string {
	lo, hi := sorted_selection(e)
	return string(e.builder.buf[lo:hi])
}

editor_cut :: proc(e: ^Editor) -> bool {
	if editor_copy(e) {
		lo, hi := min(e.selection[0], e.selection[1]), max(e.selection[0], e.selection[1])
		selection_delete(e)
		return true
	}
	return false
}

editor_copy :: proc(e: ^Editor) -> bool {
	if e.set_clipboard != nil {
		return e.set_clipboard(e.clipboard_user_data, current_selected_text(e))
	}
	return e.set_clipboard != nil
}

editor_paste :: proc(e: ^Editor) -> bool {
	if e.get_clipboard == nil {
		return false
	}
	str := e.get_clipboard(e.clipboard_user_data) or_return
	a: bool
	str, a = strings.replace_all(str, "\t", " ") // this should never allocate
	if e.get_clipboard != nil {
		input_text(e, str)
	}
	if a {
		delete(str)
	}
	return true
}

editor_execute :: proc(e: ^Editor, cmd: Command) {
	assert(e.builder != nil)
	if int(cmd) > 2 {
		undo_clear(e, &e.redo)
		append(&e.undo, Undo_Action{
			selection = e.selection,
			text = strings.clone_from_bytes(e.builder.buf[:], e.undo_text_allocator),
		})
		if len(e.undo) > MAX_UNDO {
			pop_front(&e.undo)
		}
	}
	switch cmd {
	case .None:              /**/
	case .Undo:              editor_undo(e, &e.undo, &e.redo)
	case .Redo:              editor_undo(e, &e.redo, &e.undo)
	case .New_Line:          input_text(e, "\n")
	case .Cut:               editor_cut(e)
	case .Copy:              editor_copy(e)
	case .Paste:             editor_paste(e)
	case .Select_All:        e.selection = {len(e.builder.buf), 0}
	case .Backspace:         delete_to(e, .Left)
	case .Delete:            delete_to(e, .Right)
	case .Delete_Word_Left:  delete_to(e, .Word_Left)
	case .Delete_Word_Right: delete_to(e, .Word_Right)
	case .Left:              move_to(e, .Left)
	case .Right:             move_to(e, .Right)
	case .Up:                move_to(e, .Up)
	case .Down:              move_to(e, .Down)
	case .Word_Left:         move_to(e, .Word_Left)
	case .Word_Right:        move_to(e, .Word_Right)
	case .Start:             move_to(e, .Start)
	case .End:               move_to(e, .End)
	case .Line_Start:        move_to(e, .Soft_Line_Start)
	case .Line_End:          move_to(e, .Soft_Line_End)
	case .Select_Left:       select_to(e, .Left)
	case .Select_Right:      select_to(e, .Right)
	case .Select_Up:         select_to(e, .Up)
	case .Select_Down:       select_to(e, .Down)
	case .Select_Word_Left:  select_to(e, .Word_Left)
	case .Select_Word_Right: select_to(e, .Word_Right)
	case .Select_Start:      select_to(e, .Start)
	case .Select_End:        select_to(e, .End)
	case .Select_Line_Start: select_to(e, .Soft_Line_Start)
	case .Select_Line_End:   select_to(e, .Soft_Line_End)
	}
}
