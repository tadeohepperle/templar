package templar

import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"


// /////////////////////////////////////////////////////////////////////////////
// Public interface

// call this when your program (or the part dealing with translations) is done
cleanup_languages :: proc() {
	_global_cleanup()
}
tr_to_builder :: proc(s: string, builder: ^strings.Builder, args: ..Value) -> (ok: bool) {
	translated, err := execute(GLOBAL.CURRENT.mod, s, args, builder)
	if err, is_err := err.(string); is_err {
		strings.builder_reset(builder)
		strings.write_string(builder, err)
		return false
	}
	return true
}

tr :: proc(
	s: string,
	args: ..Value,
	allocator := context.allocator,
) -> (
	res: string,
	ok: bool,
) #optional_ok {
	builder := builder(allocator)
	translated, err := execute(GLOBAL.CURRENT.mod, s, args, &builder)
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
			load_language_from_path(file.fullpath) or_return
			n += 1
		}
	}
	if n == 0 {
		return 0, tprint("directory", dir_path, "did not contain any .templar files")
	}
	return n, nil
}
load_language_from_path :: proc(file_path: string) -> Error {
	if filepath.ext(file_path) != ".templar" {
		return "filepath should end with .templar"
	}
	slugname: string = filepath.short_stem(file_path)
	if slugname == "" {
		return "slugname of language is empty!"
	}
	for l in GLOBAL.LANGUAGES {
		if l.slugname == slugname {
			return tprint("language with slugname", slugname, "already registered!")
		}
	}

	info, err := os.stat(file_path, context.temp_allocator)
	if err != nil {
		return tprint("file stat could not be loaded:", file_path)
	}
	source, success := os.read_entire_file(file_path, context.allocator)
	defer delete(source)
	if !success {
		return tprint("file not found:", file_path)
	}
	_global_maybe_init()

	arena := _global_arena_alloc()
	lang: Language
	lang.source = strings.clone(transmute(string)source, arena)
	tokens := tokenize(lang.source, context.temp_allocator) or_return
	lang.mod = parse_module(tokens, arena) or_return
	lang.slugname = strings.clone(slugname, arena)
	// give languages opportunity to declare their own name for example as LANG_NAME = "中文", while the file can be named chinese.templar
	tbuilder := builder(context.allocator)
	if name, err := execute(lang.mod, LANG_NAME_DECL, nil, &tbuilder); err == nil {
		lang.native_name = strings.clone(name, arena)
	} else {
		lang.native_name = strings.clone(slugname, arena)
	}
	lang.modification_time = info.modification_time
	lang.file_path = strings.clone(file_path, arena)
	append(&GLOBAL.LANGUAGES, lang)
	if GLOBAL.CURRENT.slugname == "" {
		GLOBAL.CURRENT = lang
	}
	return nil
}
SlugAndNativeName :: struct {
	slugname:     string,
	display_name: string,
}
get_current_language :: proc() -> SlugAndNativeName {
	return {GLOBAL.CURRENT.slugname, GLOBAL.CURRENT.native_name}
}
get_all_languages :: proc() -> []SlugAndNativeName {
	res := make([]SlugAndNativeName, len(GLOBAL.LANGUAGES), context.temp_allocator)
	for lang, idx in GLOBAL.LANGUAGES {
		res[idx] = SlugAndNativeName{lang.slugname, lang.native_name}
	}
	return res
}
set_language :: proc(slugname: string) -> (success: bool) {
	if GLOBAL.CURRENT.slugname == slugname {
		return true
	}
	for lang in GLOBAL.LANGUAGES {
		if lang.slugname == slugname {
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
	slugname:          string,
	native_name:       string,
	source:            string,
	// note: tokens not stored, they are just temporarily created to make parsing easier. 
	// They don't hold allocations anyway, idents and string literals point into the source directly.
	mod:               Module,
	file_path:         string,
	modification_time: time.Time,
}
LANG_NAME_DECL :: "LANG_NAME"

// Note: this currently leaks memory on hot-reload, because once allocated in the arena, 
// stuff is never freed, but this should not be too big of an issue.
// in production you should not hot reload of course
hot_reload_languages :: proc() {
	for &lang in GLOBAL.LANGUAGES {
		fi, err := os.stat(lang.file_path, context.temp_allocator)
		if err != nil {
			log.info("Error reading file: ")
		}
		if fi.modification_time._nsec <= lang.modification_time._nsec do continue
		// try hot reload:
		source_bytes, success := os.read_entire_file(lang.file_path, context.allocator)
		defer delete(source_bytes)
		if !success {
			log.info("Error reading file: ", lang.file_path)
		}

		arena := _global_arena_alloc()
		source := strings.clone(transmute(string)source_bytes, arena)
		tokens, token_err := tokenize(source, context.temp_allocator)
		lang.modification_time = fi.modification_time
		if err, is_err := token_err.(string); is_err {
			log.info("Error tokenizing", lang.file_path, ":", err)
			continue
		}
		module, module_err := parse_module(tokens, arena)
		if err, is_err := module_err.(string); is_err {
			log.info("Error parsing", lang.file_path, ":", err)
			continue
		}
		log.info("Hot reloaded ", lang.file_path)
		lang.source = source
		lang.mod = module
		tbuilder := builder(context.allocator)
		if name, err := execute(lang.mod, LANG_NAME_DECL, nil, &tbuilder); err == nil {
			lang.native_name = strings.clone(name, arena)
		} else {
			lang.native_name = strings.clone(lang.slugname, arena)
		}

		if GLOBAL.CURRENT.slugname == lang.slugname {
			GLOBAL.CURRENT = lang
		}


	}
}
