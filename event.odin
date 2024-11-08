package onyx

Event_Type :: enum {
	Hover,
	Press,
	Release,
	Click,
	Toggle,
}

Object_Tags :: bit_set[0..<64]

Event :: struct {
	type: Event_Type,
	name: string,
	tags: Object_Tags,
	point: [2]f32,
}
