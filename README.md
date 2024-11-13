# Onyx
**The vision**: Beautiful immediate-mode gui with advanced layouts that runs as fast as your monitor.

![image](preview.png)

## What?
This library is designed by me, for me, based on what I like, but it's quite customizable.

## How?
Onyx uses GLFW for windowing and [vgo](https://github.com/isaiah-parton/vgo) for graphics.

I've done away with the past rect-cut layout method and introduced centered layouts and layouts with unknown sizes.  The library internally decides if an object needs to be deferred or rendered immediately, losing no immediate-mode functionality.  The overhead for this is quite minimal and most of it is only present when advanced layouts are actually used.

## Can I use it?
Not yet.  This project is still experimental, though I do plan on making some desktop apps with it in the future.  It has no docs and calling it stable is still a stretch.

**Note**: you must also have the [vgo](https://github.com/isaiah-parton/vgo) package in the same folder as onyx

## Ok, and?

Stuff i'm working on:
- Making the library stable again
- Popups
- Forms for tab focusing
