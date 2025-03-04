package templar


import "core:fmt"
print :: fmt.println
main :: proc() {
	// STR :: `rep3(foo) = {foo ","  foo "," foo}`
	// STR :: `foo(a,b) = {b a b} `
	// STR :: `foo(a) = if a == "hello" {"wow"} else "meh"`
	// STR :: `rep3(foo: bool) = {foo ","  foo "," foo}`

	STR :: `TWO(x) = {x x}    FOO(s) = {if s == "tadeo" { "yay " TWO({ "buba"}) } else "nay"}`
	res, err := run(STR, "FOO", {"tadeso"})
	if err != nil {
		print("ERROR:")
		print(err)
	} else {
		print("SUCCESS:")
		print(res)
	}
}

/*



foo in [ 1: "1", _:"" ]


{
    t_string = "foo" in [...]
    t_string
}

*/
