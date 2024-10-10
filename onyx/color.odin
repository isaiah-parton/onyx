package onyx

import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:strconv"
import "core:strings"

Color :: [4]u8

parse_rgba :: proc(str: string) -> (res: Color, ok: bool) {
	strs := strings.split(str, ", ")
	defer delete(strs)
	if len(strs) == 0 || len(strs) > 4 {
		return
	}
	for s, i in strs {
		num := strconv.parse_u64(s) or_return
		res[i] = u8(min(num, 255))
	}
	ok = true
	return
}

color_from_hex :: proc(hex: u32) -> Color {
	return transmute(Color)bits.reverse_bits(hex << 8)
}

hex_from_color :: proc(color: Color) -> u32 {
	return bits.reverse_bits(transmute(u32)color) >> 8
}

hsva_from_color :: proc(color: Color) -> (hsva: [4]f32) {
	rgba: [4]f32 = {f32(color.r), f32(color.g), f32(color.b), f32(color.a)} / 255

	low := min(rgba.r, rgba.g, rgba.b)
	high := max(rgba.r, rgba.g, rgba.b)
	hsva.w = rgba.a

	hsva.z = high
	delta := high - low

	if delta < 0.00001 {
		return
	}

	if high > 0 {
		hsva.y = delta / high
	} else {
		return
	}

	if rgba.r >= high {
		hsva.x = (rgba.g - rgba.b) / delta
	} else {
		if rgba.g >= high {
			hsva.x = 2.0 + (rgba.b - rgba.r) / delta
		} else {
			hsva.x = 4.0 + (rgba.r - rgba.g) / delta
		}
	}

	hsva.x *= 60

	if hsva.x < 0 {
		hsva.x += 360
	}

	return
}
color_from_hsva :: proc(hsva: [4]f32) -> Color {
	r, g, b, k, t: f32

	k = math.mod(5.0 + hsva.x / 60.0, 6)
	t = 4.0 - k
	k = clamp(min(t, k), 0, 1)
	r = hsva.z - hsva.z * hsva.y * k

	k = math.mod(3.0 + hsva.x / 60.0, 6)
	t = 4.0 - k
	k = clamp(min(t, k), 0, 1)
	g = hsva.z - hsva.z * hsva.y * k

	k = math.mod(1.0 + hsva.x / 60.0, 6)
	t = 4.0 - k
	k = clamp(min(t, k), 0, 1)
	b = hsva.z - hsva.z * hsva.y * k

	return {u8(r * 255.0), u8(g * 255.0), u8(b * 255.0), u8(hsva.a * 255.0)}
}

hsl_from_norm_rgb :: proc(rgb: [3]f32) -> [3]f32 {
	v := max(rgb.r, rgb.g, rgb.b)
	c := v - min(rgb.r, rgb.g, rgb.b)
	f := 1 - abs(v + v - c - 1)
	h := ((rgb.g - rgb.b) / c) if (c > 0 && v == rgb.r) else ((2 + (rgb.b - rgb.r) / c) if v == rgb.g else (4 + (rgb.r - rgb.g) / c))
	return {60 * ((h + 6) if h < 0 else h), (c / f) if f > 0 else 0, (v + v - c) / 2}
}

color_from :: proc {
	color_from_hex,
	color_from_hsl,
	color_from_hsva,
}

lerp_colors :: proc(time: f32, colors: ..Color) -> Color {
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
