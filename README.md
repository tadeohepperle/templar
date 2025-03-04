# templar - a small DSL for string composition with conditional grammar

Often you want to display strings to users that are derived from structured data.
There are two problems:

- often the strings need to change based on the data. E.g. "You ordered 3 items", vs. "You ordered 1 item"
- different languages have different grammar rules that

Comparable to [ICU Message format](https://lokalise.com/blog/complete-guide-to-icu-message-format/), but writes more like a programming language and is probably less featureful.

Main idea: there is an implicit output buffer that strings are appended to as the code is interpreted.

# Syntax and Examples:

### Simple key value definitions:

You can start out by using templar like a json file for translated strings:

```c
// e.g. English in one file:
SUCCESS_BTN_TEXT = "Success!"
WELCOME = "Welcome"
ARE_YOU_SURE = "Are you sure you want to close the app?"
// e.g. German in another file:
SUCCESS_BTN_TEXT = "Erfolg!"
WELCOME = "Willkommen"
ARE_YOU_SURE = "Bist du sicher, dass du das Programm schließen willst?"
```

Comments are all lines that start with `//`

### Functions and groups:

You can create simple funcions that construct strings. Functions have arguments. You can specify the type of arguments with `my_arg: Type`. Currently only the types `str` (string), `int` (natural numbers) and `bool` (true vs. false) are supported.
Argument types are checked at runtime. If you omit the argument type, the function accepts arguments of any of the 3 types:

```c
twice(x) = {x x}
// twice("boo") == "boo boo"
greet(name) = {"Hello" name "you are awesome!"}
// greet("James") == "Hello James you are awesome!"
```

Spaces are automatically added in between, if the last thing added to the output did not end with a space already. If this is not desired, you can prefix any expression with `+` to bind it to the last word without a space in between:

```c
greet(name: str) = {"Hello" name +"!"}
// greet(name) == "Hello James!"
```

Whitespace and commas do not matter (except for inside quoted strings), you can spread anything across lines.
You can also use format strings like in JavaScript or Python, as some nicer syntax:

```c
more(x) = {x +"00"}
description(name: str, age: int) = "I am {name} and {more(age)} years old."
// description("Hans", 13) == "I am Hans and 1300 years old."
```

Top level order of declarations does not matter.

### Control flow:

You can use if-else statements:

```c
cart(n: int) = {
    "The cart contains "
    if n == 0 {
        "no"
    } else {
        n
    }
    "item"
    if n != 1 { +"s" }
}
// cart(0) == "The cart contains no items"
// cart(1) == "The cart contains 1 item"
// cart(34) == "The cart contains 2 items"
```

This can be written in a short way too:

```c
cart(n: int) = {
    "The cart contains "
    if n == 0 "no" else n
    if n == 1 "item" else "items"
}
```

You can also `return` early like this:

```c
cart(n: int) = {
    if n == 0 {
        "Go buy more"
        return
    }
    "The cart contains {n} item" if n != 1 +"s"
}
// cart(0) == "Go buy more"
// cart(1) == "The cart contains 1 item"
// cart(34) == "The cart contains 34 items"
```

Switch statements can be used for table-lookups.

```c
cart(n: int) = {
    switch n {
        0: "No items"
        1: "One item"
        2: "Two Items"
    }
}
// cart(1) == "One item"
// cart(34) == "" because we did not cover it.
```

We can attach an `else` branch to a switch statement that is executed when no case maches:

```c
roman(x: int) = switch x {
	1: "I",
	2: "II",
	3: "III",
	4: "IV",
	5: "V",
	6: "VI",
} else "{x} is too high"
// roman(4) == "IV"
// roman(123) == "123 is too high"
```

Currently the values that are compared to in a switch statement need to be constant numbers or strings. String tables are great for e.g. enums that need to be translated:

```c
CHESS_PIECE(name: str) = switch name {
    "PAWN": "Bauer"
    "KNIGHT": "Springer"
    "KING": "König"
    "ROOK": "Turm"
    "BISHOP": "Läufer"
} else "UNKNOWN"
```

### More examples:

You can capitilize an expression by adding `#cap` in front of it:

```c
sentence(a, b, dmg) = {
	#cap a "deal" if a != "you" +"s" "{dmg} damage to {b}."
}
// note the capitalization:
// sentence("you", "the bandit", 3) == "You deal 3 damage to the bandit."
// sentence("the bandit", "you", 5) == "The bandit deals 5 damage to you."
```

You can use `#todo` or `...` to mark a value as missing. If this is encountered during execution an error string is returned. This can help you find places that do not have translations yet.

```c
APPLE = ...
PEACH = ...
FOO(x) = #todo
```

```c
damage(x: int, to: str, range: int, is_fire: bool) {
    "You deal" if x == 0 "no" else x
    if is_fire and x > 0 "fire"
    "damage to"
    if range == 0 {
        "yourself"
    } else if range > 1 {
        to "next to you"
    } else {
        to "at most" range "tiles apart from you"
    }
}
// damage(10, "a character", 1, true) == "You deal 10 fire damage to a character next to you"
// damage(5, "a character", 0, false) == "You deal 5 damage to yourself"
```
