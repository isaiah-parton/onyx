package onyx

Table_Field_Type :: enum {
	Integer,
	Real,

}

Table_Field_Info :: struct {

}

Table_Entry :: struct {

}

Table_Info :: struct {
	using _: Generic_Widget_Info,
	fields: []Table_Field_Info,
	entries: []Table_Entry,
}