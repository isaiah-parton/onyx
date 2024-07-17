package ui

Widget :: struct {
	id: Id,
	box: Box,
	dead: bool,
}
Widget_Result :: struct {

}

Button_Desc :: struct {
	text: string,
}
/*
	Measure the minimum required size of the button to fit its label
*/
measure_button :: proc(desc: Button_Desc) -> (width: f32) {
	return
}
/*
	Display, update and return last frame's state
*/
button :: proc(desc: Button_Desc, loc := #caller_location) -> (res: Widget_Result) {

	return
}