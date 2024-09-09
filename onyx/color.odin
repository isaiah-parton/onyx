package onyx

import "core:math"
import "core:math/linalg"

Color :: [4]u8

interpolate_colors :: proc(time: f32, colors: ..Color) -> Color {
	if len(colors) > 0 {
		if len(colors) == 1 {
			return colors[0]
		}
		if time <= 0 {
			return colors[0]
		} else if time >= f32(len(colors) - 1) {
			return colors[len(colors) - 1]
		} else {
			i := int(math.floor(time))
			t := time - f32(i)
			return(
				colors[i] +
				{
						u8((f32(colors[i + 1].r) - f32(colors[i].r)) * t),
						u8((f32(colors[i + 1].g) - f32(colors[i].g)) * t),
						u8((f32(colors[i + 1].b) - f32(colors[i].b)) * t),
						u8((f32(colors[i + 1].a) - f32(colors[i].a)) * t),
					} \
			)
		}
	}
	return {}
}

set_color_brightness :: proc(color: Color, value: f32) -> Color {
	delta := clamp(i32(255.0 * value), -255, 255)
	return {
		cast(u8)clamp(i32(color.r) + delta, 0, 255),
		cast(u8)clamp(i32(color.g) + delta, 0, 255),
		cast(u8)clamp(i32(color.b) + delta, 0, 255),
		color.a,
	}
}

get_color_brightness :: proc(color: Color) -> f32 {
	return f32(color.r / 255) * 0.3 + f32(color.g / 255) * 0.59 + f32(color.b / 255) * 0.11
}

color_to_hsl :: proc(color: Color) -> [4]f32 {
	hsva := linalg.vector4_rgb_to_hsl(
		linalg.Vector4f32 {
			f32(color.r) / 255.0,
			f32(color.g) / 255.0,
			f32(color.b) / 255.0,
			f32(color.a) / 255.0,
		},
	)
	return hsva.xyzw
}

color_from_hsl :: proc(hue, saturation, value: f32) -> Color {
	rgba := linalg.vector4_hsl_to_rgb(hue, saturation, value, 1.0)
	return {u8(rgba.r * 255.0), u8(rgba.g * 255.0), u8(rgba.b * 255.0), u8(rgba.a * 255.0)}
}

fade :: proc(color: Color, alpha: f32) -> Color {
	return {color.r, color.g, color.b, u8(f32(color.a) * alpha)}
}

alpha_blend_colors_tint :: proc(dst, src, tint: Color) -> (out: Color) {
	out = 255

	src := src
	src.r = u8((u32(src.r) * (u32(tint.r) + 1)) >> 8)
	src.g = u8((u32(src.g) * (u32(tint.g) + 1)) >> 8)
	src.b = u8((u32(src.b) * (u32(tint.b) + 1)) >> 8)
	src.a = u8((u32(src.a) * (u32(tint.a) + 1)) >> 8)

	if (src.a == 0) {
		out = dst
	} else if src.a == 255 {
		out = src
	} else {
		alpha := u32(src.a) + 1
		out.a = u8((u32(alpha) * 256 + u32(dst.a) * (256 - alpha)) >> 8)

		if out.a > 0 {
			out.r = u8(
				((u32(src.r) * alpha * 256 + u32(dst.r) * u32(dst.a) * (256 - alpha)) /
					u32(out.a)) >>
				8,
			)
			out.g = u8(
				((u32(src.g) * alpha * 256 + u32(dst.g) * u32(dst.a) * (256 - alpha)) /
					u32(out.a)) >>
				8,
			)
			out.b = u8(
				((u32(src.b) * alpha * 256 + u32(dst.b) * u32(dst.a) * (256 - alpha)) /
					u32(out.a)) >>
				8,
			)
		}
	}
	return
}

alpha_blend_colors_time :: proc(dst, src: Color, time: f32) -> (out: Color) {
	return alpha_blend_colors_tint(dst, src, fade(255, time))
}

alpha_blend_colors :: proc {
	alpha_blend_colors_time,
	alpha_blend_colors_tint,
}
