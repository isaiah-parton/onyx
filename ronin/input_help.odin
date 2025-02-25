package ronin

import "core:unicode/utf8"

fuzzy_match :: proc(match, text: string) -> int {
	matching_runes: int
	match_index: int
	match_rune, match_rune_bytes := utf8.decode_rune_in_string(match[match_index:])
	for text_rune in text {
		if match_rune == text_rune {
			match_index += match_rune_bytes
			matching_runes += 1
			match_rune, match_rune_bytes = utf8.decode_rune_in_string(match[match_index:])
		}
	}
	return matching_runes
}

match_start :: proc(match, text: string) -> int {
	matching_runes: int
	match_index: int
	for text_rune in text {
		match_rune, match_rune_bytes := utf8.decode_rune_in_string(match[match_index:])
		if match_rune == text_rune {
			matching_runes += 1
		} else {
			if len(match) > match_index {
				matching_runes = 0
			}
			break
		}
		match_index += match_rune_bytes
	}
	return matching_runes
}
