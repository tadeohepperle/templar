package templar

import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:strings"


// /////////////////////////////////////////////////////////////////////////////
// Public interface

// call this when your program (or the part dealing with translations) is done
cleanup_languages :: proc() {
	_global_cleanup()
}
tr :: proc(
	s: string,
	args: ..Value,
	allocator := context.temp_allocator,
) -> (
	res: string,
	ok: bool,
) #optional_ok {
	translated, err := execute(GLOBAL.CURRENT.mod, s, args, allocator)
	if err, is_err := err.(string); is_err {
		return err, false
	}
	return translated, true
}
// load all files in dir with `.templar` file extension
load_all_languages_in_dir :: proc(dir_path: string) -> (n: int, err: Error) {
	handle, open_err := os.open(dir_path)
	if open_err != nil {
		return 0, tprint("directory", dir_path, "could not be opened:", open_err)
	}
	files, read_err := os.read_dir(handle, -1, context.temp_allocator)
	if read_err != nil {
		return 0, tprint("directory", dir_path, "could not be read:", read_err)
	}
	for file in files {
		if !file.is_dir && strings.ends_with(file.name, ".templar") {
			load_language_from_path(file.name, file.fullpath) or_return
			n += 1
		}
	}
	if n == 0 {
		return 0, tprint("directory", dir_path, "did not contain any .templar files")
	}
	return n, nil
}
load_language_from_path :: proc(language_name: string, file_path: string) -> Error {
	for l in GLOBAL.LANGUAGES {
		if l.name == language_name {
			return tprint("language name", language_name, "already registered!")
		}
	}
	source, success := os.read_entire_file(file_path, context.allocator)
	defer delete(source)
	if !success {
		return tprint("file not found:", file_path)
	}
	_global_maybe_init()
	lang := language_from_string(
		language_name,
		transmute(string)source,
		_global_arena_alloc(),
	) or_return
	append(&GLOBAL.LANGUAGES, lang)
	if GLOBAL.CURRENT.name == "" {
		GLOBAL.CURRENT = lang
	}
	return nil
}
get_current_langauge_name :: proc() -> string {
	return GLOBAL.CURRENT.name
}
get_all_language_names :: proc() -> []string {
	res := make([]string, len(GLOBAL.LANGUAGES), context.temp_allocator)
	for lang, idx in GLOBAL.LANGUAGES {
		res[idx] = lang.name
	}
	return res
}
set_language :: proc(language_name: string) -> (success: bool) {
	if GLOBAL.CURRENT.name == language_name {
		return true
	}
	for lang in GLOBAL.LANGUAGES {
		if lang.name == language_name {
			GLOBAL.CURRENT = lang
			return true
		}
	}
	return false
}

// /////////////////////////////////////////////////////////////////////////////
// Private functions and global module state

@(private)
GLOBAL: struct {
	INITIALIZED: bool,
	ARENA:       virtual.Arena,
	CURRENT:     Language, // allocated fully in arena
	LANGUAGES:   [dynamic]Language, // allocated fully in arena
}
@(private)
_global_arena_alloc :: #force_inline proc() -> mem.Allocator {
	return virtual.arena_allocator(&GLOBAL.ARENA)
}
@(private)
_global_maybe_init :: proc() {
	if !GLOBAL.INITIALIZED {
		err := virtual.arena_init_growing(&GLOBAL.ARENA)
		assert(err == .None)
		GLOBAL.INITIALIZED = true
		GLOBAL.LANGUAGES = make([dynamic]Language, virtual.arena_allocator(&GLOBAL.ARENA))
		reserve(&GLOBAL.LANGUAGES, 64)
	}
}
@(private)
_global_cleanup :: proc() {
	virtual.arena_destroy(&GLOBAL.ARENA)
	GLOBAL.INITIALIZED = false
}
@(private)
Language :: struct {
	name:   string,
	source: string,
	// note: tokens not stored, they are just temporarily created to make parsing easier. 
	// They don't hold allocations anyway, idents and string literals point into the source directly.
	mod:    Module,
}
@(private)
language_from_string :: proc(
	language_name: string,
	source: string,
	allocator: mem.Allocator,
) -> (
	lang: Language,
	err: Error,
) {
	if language_name == "" {
		return {}, "language name is empty!"
	}

	source := strings.clone(source, allocator)

	tokens := tokenize(source, context.temp_allocator) or_return
	print(language_name)
	mod := parse_module(tokens, allocator) or_return
	print("module")
	language_name := language_name
	// give languages opportunity to declare their own name for example as `LANG_NAME = "Dansk"`
	if name, err := execute(mod, LANG_NAME_DECL, nil); err == nil {
		language_name = strings.clone(name, allocator)
	}
	language_name = strings.clone(language_name, allocator)
	return Language{language_name, source, mod}, nil
}
LANG_NAME_DECL :: "LANG_NAME"
