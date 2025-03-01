package ronin

// This file contains abstractions for all of the properties used to describe layouts, panels and object sizes
//
// Add a column 100px wide on the left of the current layout
// ```
// do_layout(on_left, with_width(100), as_column)
// ```
//
// Many immediate-mode objects accept `..Property` kind of arguments and build a descriptor from that
// I can't seem to decide between making this library maximally fast or developer-friendly, but so far this seems like a nice balance
//
// Pros:
// 	- I can modify struct field names and functionality without having to change ui code
//  - New users of the library can pick it up quickly
//  - Polymorphic abstractions
// 		- For example; panels accept panel properties, but also layout properties and each sub-component handles properties of its kind
//
// Cons:
// 	- A dozen or so bytes of overhead and a few loop cycles with a union switch statement for every object, every frame
//
// I could let the user handle the `*_Descriptor` data themselves, but this would seem to defeat the purpose of the abstractions.  Using a descriptor struct would also require always checking every field, while with `..Property` only properties present are processed

golden_ratio :: 1.618033988749
phi :: golden_ratio
φ :: golden_ratio

Is_Root :: struct {}
is_root :: Is_Root{}

Split_By :: distinct f32
Define_Content_Sizes :: []f32

Exact_Width_Or_Height :: f32

Defined_Object_Width :: distinct f32
with_width :: Defined_Object_Width

Defined_Object_Height :: distinct f32
Factor_Of_Remaining_Width :: distinct f32
Factor_Of_Remaining_Height :: distinct f32
Factor_Of_Remaining_Width_Or_Height :: distinct f32
Factor_Of_Remaining_Space :: distinct [2]f32
Subtract_From_Size :: distinct f32

Alignment :: distinct f32
center_contents :: Alignment(0.5)

Exact_Size :: [2]f32
exactly :: Exact_Size

Preferred_Size_Of_Object :: struct {}
whatever :: Preferred_Size_Of_Object{}
that_of_object :: Preferred_Size_Of_Object{}

Factor_Of_Predefined_Scale :: distinct f32
to_scale :: Factor_Of_Predefined_Scale

at_most :: Size_Method.Min
at_least :: Size_Method.Max

Account_For_Spacing :: Subtract_From_Size
with_spacing :: Account_For_Spacing

to_layout_width :: Factor_Of_Remaining_Width(1)
to_layout_height :: Factor_Of_Remaining_Height(1)
to_layout_size :: Factor_Of_Remaining_Space(1)
of_layout_width :: proc(fraction: f32) -> f32 {return remaining_space().x * fraction}
of_layout_height :: proc(fraction: f32) -> f32 {return remaining_space().y * fraction}
of_layout_size :: proc(fraction: [2]f32) -> [2]f32 {return remaining_space() * fraction}

Cut_From_Side :: distinct Side
on_left :: Cut_From_Side(.Left)
on_right :: Cut_From_Side(.Right)
on_top :: Cut_From_Side(.Top)
on_bottom :: Cut_From_Side(.Bottom)

Cut_Contents_From_Side :: distinct Side
left_to_right :: Cut_Contents_From_Side(.Left)
right_to_left :: Cut_Contents_From_Side(.Right)
top_to_bottom :: Cut_Contents_From_Side(.Top)
bottom_to_top :: Cut_Contents_From_Side(.Bottom)
as_row :: left_to_right
as_reversed_row :: right_to_left
as_column :: top_to_bottom
as_reversed_column :: bottom_to_top

Defined_Position :: distinct [2]f32
Defined_Size :: distinct [2]f32
Defined_Box :: distinct Box
Padding :: distinct [4]f32
Margin :: distinct [4]f32
with_box :: Defined_Box
with_position :: Defined_Position
with_size :: Defined_Size
with_margin :: Margin
with_padding :: Padding

Split_Into :: distinct f32
split_halves :: Split_Into(2)
split_thirds :: Split_Into(3)
split_fourths :: Split_Into(4)
split_fifths :: Split_Into(5)
split_sixths :: Split_Into(6)
split_sevenths :: Split_Into(7)
split_golden :: Split_Into(golden_ratio)

Panel_Can_Resize :: distinct bool
Panel_Can_Snap :: distinct bool
Layout_Is_Dynamic :: distinct bool
is_dynamic :: Layout_Is_Dynamic(true)
with_sorting :: Layer_Sort_Method
that_can_resize :: Panel_Can_Resize(true)
without_snapping :: Panel_Can_Snap(false)
