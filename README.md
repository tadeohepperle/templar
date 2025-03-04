# templar - a small DSL for string composition with conditional grammar

Often you want to display strings to users that are derived from structured data.
There are two problems:

- often the strings need to change based on the data. E.g. "You ordered 3 items", vs. "You ordered 1 item"
- different languages have different grammar rules that

Comparable to [ICU Message format](https://lokalise.com/blog/complete-guide-to-icu-message-format/), but writes more like a programming language.

Main idea: there is an implicit output buffer that strings are appended to as the code is interpreted

Examples and syntax docs will follow soon...

```js
three_times(x) = {x x x}
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
// can be called like this:
// damage(10, "a character", 1, true) -> "You deal 10 fire damage to a character next to you"
// damage(5, "a character", 0, false) -> "You deal 5 damage to yourself"
```
