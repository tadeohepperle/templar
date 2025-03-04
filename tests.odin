package templar

import "core:testing"

@(test)
tests :: proc(t: ^testing.T) {

	CAP :: `
	test(a, b, dmg) = {
		#cap a "deal" if a != "you" +"s" "{dmg} damage to" b +"."
	}`


	expect(t, CAP, "You deal 3 damage to the bandit.", "you", "the bandit", 3)
	expect(t, CAP, "The bandit deals 5 damage to you.", "the bandit", "you", 5)

	ROMAN :: `test(x: int) = switch x {
		1: "I",
		2: "II",
		3: "III",
		4: "IV",
		5: "V",
		6: "VI",
	} else "{x} is too high"
    `


	expect(t, ROMAN, "IV", 4)
	expect(t, ROMAN, "II", 2)
	expect(t, ROMAN, "23 is too high", 23)
	expect_fail(t, ROMAN, "23") // because of x: int

	DAMAGE :: `
    test(x, to: str, range: int, is_fire: bool) = {
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
	}
`


	expect(
		t,
		DAMAGE,
		"You deal 10 fire damage to a character next to you",
		10,
		"a character",
		1,
		true,
	)
	expect(t, DAMAGE, "You deal 5 damage to yourself", 5, "a character", 0, false)
	expect(
		t,
		DAMAGE,
		"You deal 22 damage to a character who is 3 or less tiles apart from you",
		22,
		"a character",
		3,
		false,
	)
}
expect :: proc(t: ^testing.T, src: string, expected: string, args: ..Value) {
	res, err := run(src, "test", args)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, res, expected)
}

expect_fail :: proc(t: ^testing.T, src: string, args: ..Value) {
	res, err := run(src, "test", args)
	testing.expect(t, err != nil)
}
