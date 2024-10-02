# Onyx

This is my immediate-mode ui library that I'm making for some desktop apps I have in mind.  It's currently nowhere near production-ready, I'm still working out the core functionality, but it already has a lot of widgets.
It is not renderer or platform agnostic, but by using GLFW and WGPU, I hope to bring it to every desktop platform.  It's not meant to be integrated into existing projects like dear imgui, but rather for creating tools and desktop apps.
I'm currently finalizing the layout functionality before I move ahead with more widgets and things.

## Here's the gist of how it works:

Layer -> Something you render to, it has a z-index for ordered rendering and it's own root layout.

Layout -> A box from which you cut other boxes for more layouts, widgets, etc...

Container -> A scrollable area

Widget -> Something you click on (sometimes not, example: calendars)

Panel -> A decorated layer you can drag around and resize.

## How can I center something?

Widgets are transient objects that are initialized and added every frame.  Initializing something will always compute it's desired size, which can be used to center the layout it will be displayed in.
For example, this is what happens when you call the `button` proc:
```
info := info
if init_button(&info, loc) {
	add_button(&info)
}
return info
```
The info passed to the procedure is made mutable, then initialized and added.  The modified info is then returned.

## Todo

- [ ] Popups
