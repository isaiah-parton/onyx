package onyx

import "base:runtime"
import "core:fmt"

Id :: u32

FNV1A64_OFFSET_BASIS :: 0xcbf29ce484222325
FNV1A64_PRIME :: 0x00000100000001B3
fnv64a :: proc(data: []byte, seed: u64) -> u64 {
	h: u64 = seed;
	for b in data {
		h = (h ~ u64(b)) * FNV1A64_PRIME;
	}
	return h;
}
FNV1A32_OFFSET_BASIS :: 0x811c9dc5
FNV1A32_PRIME :: 0x01000193
fnv32a :: proc(data: []byte, seed: u32) -> u32 {
	h: u32 = seed;
	for b in data {
		h = (h ~ u32(b)) * FNV1A32_PRIME;
	}
	return h;
}
/*
	Unique id creation
*/
hash :: proc {
	hash_string,
	hash_rawptr,
	hash_uintptr,
	hash_bytes,
	hash_loc,
	hash_int,
}
hash_int :: #force_inline proc(num: int) -> Id {
	hash := global_state.id_stack.items[global_state.id_stack.height - 1] if global_state.id_stack.height > 0 else FNV1A32_OFFSET_BASIS
	return hash ~ (Id(num) * FNV1A32_PRIME)
}
hash_string :: #force_inline proc(str: string) -> Id {
	return hash_bytes(transmute([]byte)str)
}
hash_rawptr :: #force_inline proc(data: rawptr, size: int) -> Id {
	return hash_bytes(([^]u8)(data)[:size])
}
hash_uintptr :: #force_inline proc(ptr: uintptr) -> Id {
	ptr := ptr
	return hash_bytes(([^]u8)(&ptr)[:size_of(ptr)])
}
hash_bytes :: proc(bytes: []byte) -> Id {
	return fnv32a(bytes, global_state.id_stack.items[global_state.id_stack.height - 1] if global_state.id_stack.height > 0 else FNV1A32_OFFSET_BASIS)
}
hash_loc :: proc(loc: runtime.Source_Code_Location) -> Id {
	hash := hash_bytes(transmute([]byte)loc.file_path)
	hash = hash ~ (Id(loc.line) * FNV1A32_PRIME)
	hash = hash ~ (Id(loc.column) * FNV1A32_PRIME)
	return hash
}

push_id_int :: proc(num: int) {
	push_stack(&global_state.id_stack, hash_int(num))
}
push_id_string :: proc(str: string) {
	push_stack(&global_state.id_stack, hash_string(str))
}
push_id_other :: proc(id: Id) {
	push_stack(&global_state.id_stack, id)
}
push_id :: proc {
	push_id_int,
	push_id_string,
	push_id_other,
}

pop_id :: proc() {
	pop_stack(&global_state.id_stack)
}
