class_name DialogueTokens
extends RefCounted

## How it works:
## - Authored dialogue may hold {tokens}; this replaces them at the moment a line
##   is presented, so the text a player reads can name their own totals.
## - Every token resolves from the lifetime record and from the device the game
##   is running on. Nothing here reads the run: the Thief is not talking about
##   this descent, he is talking about all of them.
## - A line with no braces is returned untouched and costs one find() to prove
##   it, which is what almost every line in the game is.
## - An unknown token is left standing rather than blanked, so a typo shows up as
##   itself on screen instead of as a hole in a sentence.
## - The invariant is that resolution never fails: a record with nothing in it
##   still produces grammatical English.

## The share of the way through the player's hours that the finale reaches back
## to when it asks whether they remember one. Three quarters lands on hour 6 of
## 8, which is the pair the script was written against.
const _RECALLED_HOUR_FRACTION: float = 0.75

const _WEEKDAY_NAMES: PackedStringArray = [
	"sunday",
	"monday",
	"tuesday",
	"wednesday",
	"thursday",
	"friday",
	"saturday",
]


## Returns the line with every known token replaced.
static func resolve(text: String, history: PlayerHistoryRecord) -> String:
	if history == null or text.find("{") < 0:
		return text
	var resolved := text
	var values := _build_values(history)
	for token_name in values:
		resolved = resolved.replace("{%s}" % token_name, values[token_name])
	return resolved


## Returns every token's current value, keyed without its braces.
static func _build_values(
	history: PlayerHistoryRecord
) -> Dictionary[String, String]:
	var parts := history.get_play_time_parts()
	var is_touch := history.is_touch_device()
	var recalled_hour := get_recalled_hour(history)
	var recalled := _describe_hour_completion(history, recalled_hour)
	return {
		"hours": str(parts.x),
		"minutes": str(parts.y),
		"seconds": str(parts.z),
		"presses": group_thousands(history.primary_action_presses),
		"press_target": "screen" if is_touch else "space bar",
		"click": "Tap" if is_touch else "Click",
		"device_choice": (
			"You chose to open your phone,"
			if is_touch
			else "You chose to sit at your computer,"
		),
		"device_hours": (
			"%d hours hunched over your phone"
			if is_touch
			else "%d hours seated at your computer"
		) % parts.x,
		"leave": (
			"put down your phone"
			if is_touch
			else "get up from your computer"
		),
		"early_hour": str(maxi(recalled_hour - 1, 1)),
		"late_hour": str(maxi(recalled_hour, 1)),
		"recalled_time": recalled[0],
		"recalled_day": recalled[1],
	}


## Returns the one-based hour the finale names when it asks about a middle hour.
##
## It is deliberately derived rather than fixed at the script's hour 6: the shot
## reads the player's own hours back to them, and naming an hour they never
## reached would break the only thing the scene is doing. The floor of two keeps
## the sentence grammatical for a player who somehow arrives early, and is the
## degradation the direction notes flag as open.
static func get_recalled_hour(history: PlayerHistoryRecord) -> int:
	var completed := history.get_completed_hours()
	if completed <= 0:
		return 0
	return clampi(
		int(roundf(float(completed) * _RECALLED_HOUR_FRACTION)),
		2,
		completed
	)


## Returns the clock time and the day phrase for when an hour finished, in that
## order.
##
## Both parts come back together because they are read from one timestamp and
## must describe one moment: a time from a stamp the player has and a weekday
## from a fallback would be a sentence about nothing.
static func _describe_hour_completion(
	history: PlayerHistoryRecord,
	hour: int
) -> PackedStringArray:
	var unix_time := history.get_hour_completion_unix_time(hour)
	if unix_time <= 0:
		# No stamp: either the record predates hour stamping or the hour was
		# never reached. The phrase stays vague rather than inventing a Friday.
		return PackedStringArray(["some point", "an afternoon"])
	# Stamps are UTC, and the line is about the player's own evening.
	var local_bias_seconds := (
		int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	)
	var moment := Time.get_datetime_dict_from_unix_time(
		unix_time + local_bias_seconds
	)
	var hour_of_day := int(moment.get("hour", 0))
	var minute := int(moment.get("minute", 0))
	var weekday := int(moment.get("weekday", 0))
	var clock_hour := hour_of_day % 12
	if clock_hour == 0:
		clock_hour = 12
	return PackedStringArray([
		"%d:%02d" % [clock_hour, minute],
		"%s %s" % [
			_WEEKDAY_NAMES[clampi(weekday, 0, _WEEKDAY_NAMES.size() - 1)],
			_describe_part_of_day(hour_of_day),
		],
	])


## Names the part of the day an hour of the clock falls in.
static func _describe_part_of_day(hour_of_day: int) -> String:
	if hour_of_day < 5:
		return "night"
	if hour_of_day < 12:
		return "morning"
	if hour_of_day < 17:
		return "afternoon"
	if hour_of_day < 21:
		return "evening"
	return "night"


## Returns a count with thousands separators, the way the finale prints it.
static func group_thousands(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for digit_index in range(digits.length()):
		if digit_index > 0 and (digits.length() - digit_index) % 3 == 0:
			grouped += ","
		grouped += digits[digit_index]
	return ("-" + grouped) if value < 0 else grouped
