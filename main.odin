package templar


import "core:fmt"
print :: fmt.println
main :: proc() {
	// STR :: `rep3(foo) = {foo ","  foo "," foo}`
	// STR :: `foo(a,b) = {b a b} `
	// STR :: `foo(a) = if a == "hello" {"wow"} else "meh"`
	// STR :: `rep3(foo: bool) = {foo ","  foo "," foo}`

	// STR :: `TWO(x) = {x x}    FOO(s) = {if s == "tadeo" { "yay " TWO({ "buba"}) } else "nay"}`

	STR :: `
greeting(name, age) = "I am {name} and {age} years old."
	`


	run_and_show(STR, "greeting", "Tadeo", 24)
	// run_and_show(STR, "damage", 0, "a character", 2, true)
	// run_and_show(STR, "three_times", "foo")

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
