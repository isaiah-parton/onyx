package ui

Tree_Node_Info :: struct {
	using _: Generic_Widget_Info,
	text: string,
}

begin_tree_node :: proc(info: Tree_Node_Info, loc := #caller_location) {

}

end_tree_node :: proc() {
	
}