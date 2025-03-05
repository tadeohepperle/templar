package example

import templar "../"
import "core:fmt"

main :: proc() {
	using templar
	n_langs, err := load_all_languages_in_dir("./example/")
	if err, is_err := err.(string); is_err {
		fmt.println("Error:", err)
		return
	}
	fmt.println("Loaded", n_langs, "languages:", get_all_language_names())

	assert(set_language("Deutsch"))

	print(tr("WHATS_UP"))
	print(tr("INTRO", "Tadeo", 24))
	print(tr("DATE", 2017, 3, 16))

	print("-----------------")

	assert(set_language("English"))

	print(tr("WHATS_UP"))
	print(tr("INTRO", "Tadeo", 24))
	print(tr("DATE", 2017, 3, 16))

	print("-----------------")

	assert(set_language("中文"))

	print(tr("WHATS_UP"))
	print(tr("INTRO", "Tadeo", 24))
	print(tr("DATE", 2017, 3, 16))

}
