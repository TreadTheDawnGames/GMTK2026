extends Panel
class_name TimingTarget

var is_hit : bool = false

func hit():
	is_hit = true
	hide()

func unhit():
	is_hit = false
	show()
