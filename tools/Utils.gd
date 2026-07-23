extends Node
class_name Utils

static func format_number_with_commas(number: int) -> String:
	var num_str: String = str(abs(number))
	var result: String = ""
	var count: int = 0

	for i in range(num_str.length() - 1, -1, -1):
		result = num_str[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result

	if number < 0:
		result = "-" + result

	return result
