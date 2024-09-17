# Onyx

This is my immediate-mode ui library that I'm making for some desktop apps I have in mind.  It's currently nowhere near production-ready, I'm still working out the core functionality, but it already has a lot of widgets.

It is not renderer or platform agnostic, but by using GLFW and WGPU, I hope to bring it to every desktop platform.  It's not meant to be integrated into existing projects like dear imgui, but rather for creating tools and desktop apps.

I'm currently finalizing the layout functionality before I move ahead with more widgets and things.

Here's the gist of how it works:

	Layer -> Something you render to, it has a z-index for ordered rendering and it's own root layout.
	Layout -> A box from which you cut other boxes for more layouts, widgets, etc...
	Container -> A scrollable area
	Widget -> Something you click on
	Panel -> A decorated layer you can drag around and resize. (Docking functionality is on the horizon)


How can I center something?
	Widget calls are separated into two procs: `make_widget` and `add_widget`
	`do_widget` unifies these into one call.

	`make_widget` pre-computes text layout and thus the displayed size of the widget.
	`add_widget` cuts a box from the layout and displays it, checks interaction, etc...

	Layouts also store the accumulated value of all their widget's desired sizes so auto resizing can happen on the next frame.
