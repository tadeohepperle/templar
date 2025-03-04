package templar


import "core:fmt"
print :: fmt.println
main :: proc() {


	S :: `
	sentence(a, b, dmg) = {
		#cap a "deal" if a != "you" +"s" "{dmg} damage to" b +"."
	}
	
	`


	run_and_show(S, "sentence", "you", "the bandit", 3)
	run_and_show(S, "sentence", "the bandit", "you", 5)
	if true {
		return
	}
	ROMAN :: `roman(x: int) = switch x {
		1: "I",
		2: "II",
		3: "III",
		4: "IV",
		5: "V",
		6: "VI",
	} else "{x} is too high"
	`


	run_and_show(ROMAN, "roman", 18)
	if true {return}

	run_and_show(`REROLLS_LEFT(x: int) = { x "Reroll" if x != 1 +"s" "left" }`, "REROLLS_LEFT", 1)
	run_and_show(
		`greeting(name, age) = "I am {name} and {more(age)} years old."    more(x) = {x +"000"}`,
		"greeting",
		"Tadeo",
		24,
	)
	run_and_show(`three_times(x) = {x x x +"!"}`, "three_times", "boo")
	run_and_show(`three_times(x) = "{x}-{x} {x}!"`, "three_times", "boo")


	run_and_show(DAMAGE, "damage", 0, "a character", 2, true)
	run_and_show(DAMAGE, "damage", 2, "a character", 1, true)
	run_and_show(DAMAGE, "damage", 15, "a character", 0, false)
	DAMAGE :: `
	damage(x, to: str, range: int, is_fire: bool) = {
		#cap "you deal" if x == 0 "no" else x
		if is_fire and x > 0 "fire"
		"damage to"
		if range == 0 {
			"yourself"
		} else if range == 1 {
			to "next to you"
		} else {
			to "who is" range "or less tiles apart from you"
		}
	}`


}

/*



// three_times(x) = {x x x}
// damage(x, to: str, range: int, is_fire: bool) = {
//     "You deal" if x == 0 "no" else x
//     if is_fire and x > 0 "fire"
//     "damage to"
//     if range == 0 {
//         "yourself"
//     } else if range == 1 {
//         to "next to you"
//     } else {
//         to "who is" range "or less tiles apart from you"
//     }
// }


foo in [ 1: "1", _:"" ]


{
    t_string = "foo" in [...]
    t_string
}

*/
