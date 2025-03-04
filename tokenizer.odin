package templar
import "core:strconv"
import "core:unicode/utf8"

Tokenizer :: struct {
	source:             string,
	current:            Char,
	peek:               Char,
	line:               int,
	col:                int,
	brace_depth:        int,
	string_brace_depth: int,
}
Char :: struct {
	ty:       CharType,
	ru:       rune,
	byte_idx: int,
	size:     int,
}
advance :: proc(using this: ^Tokenizer) {
	current = peek
	peek.byte_idx += peek.size
	peek.ru, peek.size = utf8.decode_rune(source[peek.byte_idx:])
	peek.ty = char_type(peek.ru)
}
advance_back :: proc(using this: ^Tokenizer) {

	peek = current
	current.ru, current.size = utf8.decode_last_rune(source[:current.byte_idx])
	current.byte_idx -= current.size
	current.ty = char_type(current.ru)

	print("advance back")
}

Token :: struct {
	ty:        TokenTy,
	using val: struct #raw_union {
		str:     string,
		number:  int,
		is_true: bool,
	},
	byte_idx:  int,
}

TokenTy :: enum {
	Error,
	Eof,
	Equal,
	EqualEqual,
	GreaterEqual,
	Greater,
	Less,
	LessEqual,
	If,
	Else,
	And,
	Or,
	LeftBrace,
	RightBrace,
	LeftBracket,
	RightBracket,
	LeftParen,
	RightParen,
	Colon,
	In,
	Ident,
	String, // "Hello"
	StringCurlyStart, //  } and I love you!"
	StringCurlyEnd, // "Hello I am {
	StringCurlyStartAndEnd, // } years old and live in {
	Number,
	Dot,
	Plus,
	Minus,
	NotEqual,
	Not,
	BoolType,
	IntType,
	StringType,
	Return,
	Todo,
}
ident_or_keyword_token :: proc(ident_name: string) -> TokenTy {
	switch ident_name {
	case "if":
		return .If
	case "in":
		return .In
	case "else":
		return .Else
	case "and":
		return .And
	case "or":
		return .Or
	case "bool":
		return .BoolType
	case "int":
		return .IntType
	case "str":
		return .StringType
	case "return":
		return .Return
	case "todo":
		return .Todo
	}
	return .Ident
}

read_number :: proc(s: ^Tokenizer) -> Token {
	start_byte := s.current.byte_idx
	for s.peek.ty == .Numeric {
		advance(s)
	}
	number_string := s.source[start_byte:s.peek.byte_idx]
	int_value, ok := strconv.parse_i64_of_base(number_string, 10)
	assert(ok)
	return Token{.Number, {number = int(int_value)}, start_byte}
}

advance_to_get_string_token :: proc(s: ^Tokenizer, curly_start: bool) -> Token {
	start_byte := s.current.byte_idx
	was_ended_by_left_brace := false
	for s.peek.ty != .DoubleQuote && s.peek.size > 0 {
		if s.peek.ty == .LeftBrace {
			if s.string_brace_depth != min(int) {
				return Token {
					.Error,
					{str = "Cannot stack multiple string literals with curly braces"},
					s.peek.byte_idx,
				}
			}
			s.brace_depth += 1
			s.string_brace_depth = s.brace_depth
			was_ended_by_left_brace = true
			break
		}
		advance(s)
	}
	string_content := s.source[start_byte + 1:s.peek.byte_idx]
	token_ty: TokenTy = ---
	if was_ended_by_left_brace {
		token_ty = .StringCurlyStartAndEnd if curly_start else .StringCurlyEnd
		// don't skip over last `{`, instead let it get handled twice by the tokonizer, to enclose everything inside the pocket as a block
	} else {
		s.string_brace_depth = min(int)
		token_ty = .StringCurlyStart if curly_start else .String
		advance(s) // skip over last DoubleQuote or an opening LeftBrace
	}
	token := Token{token_ty, {str = string_content}, start_byte}
	return token
}

read_token :: proc(s: ^Tokenizer) -> Token {
	#partial switch s.current.ty {
	case .WhiteSpace, .Comma:
		for (s.current.ty == .WhiteSpace || s.current.ty == .Comma) {
			advance(s)
		}
		if s.current.byte_idx == s.peek.byte_idx {
			return Token{.Eof, {}, s.current.byte_idx}
		} else {
			return read_token(s)
		}
	case .Letter:
		start_byte := s.current.byte_idx
		for (s.peek.ty == .Letter || s.peek.ty == .Numeric) {
			advance(s)
			if s.peek.size == 0 {
				break
			}
		}
		ident_name := s.source[start_byte:s.peek.byte_idx]
		ty := ident_or_keyword_token(ident_name)
		return Token{ty, {str = ident_name}, start_byte}
	case .DoubleQuote:
		return advance_to_get_string_token(s, false)
	case .LeftBrace:
		s.brace_depth += 1
		return Token{.LeftBrace, {}, s.current.byte_idx}
	case .RightBrace:
		if s.string_brace_depth + 1 == s.brace_depth {
			s.brace_depth -= 1
			print("meet brace +1")
			tok := Token{.RightBrace, {}, s.current.byte_idx}
			advance_back(s)
			return tok
		} else if s.string_brace_depth == s.brace_depth {
			s.string_brace_depth = min(int)
			s.brace_depth -= 1
			print("meet brace")
			return advance_to_get_string_token(s, true)
		} else {
			print("meet other brace")
			s.brace_depth -= 1
			return Token{.RightBrace, {}, s.current.byte_idx}
		}
	case .LeftBracket:
		return Token{.LeftBracket, {}, s.current.byte_idx}
	case .RightBracket:
		return Token{.RightBracket, {}, s.current.byte_idx}
	case .LeftParen:
		return Token{.LeftParen, {}, s.current.byte_idx}
	case .RightParen:
		return Token{.RightParen, {}, s.current.byte_idx}
	case .Colon:
		return Token{.Colon, {}, s.current.byte_idx}
	case .Plus:
		return Token{.Plus, {}, s.current.byte_idx}
	case .Numeric:
		return read_number(s)
	case .Equal:
		if s.peek.ty == .Equal {
			tok := Token{.EqualEqual, {}, s.current.byte_idx}
			advance(s)
			return tok
		} else {
			return Token{.Equal, {}, s.current.byte_idx}
		}
	case .Slash:
		if s.peek.ty == .Slash {
			// Double Slash is a comment. Skip over the comment line
			// skip everything until end of line:
			advance(s)
			for {
				advance(s)
				if s.current.ru == '\n' {
					break
				} else if s.current.byte_idx == s.peek.byte_idx {
					return {.Eof, {}, s.current.byte_idx - 1}
				}
			}
			return read_token(s)
		} else {
			return {
				.Error,
				{str = "expected double slash, only got single slash!"},
				s.current.byte_idx,
			}
		}
	case .Dot:
		// ... for Todo statement
		if s.peek.ty == .Dot {
			advance(s)
			if s.peek.ty == .Dot {
				advance(s)
				return Token{.Todo, {}, s.current.byte_idx - 2}
			} else {
				return Token {
					.Error,
					{str = s.source[s.current.byte_idx - 1:]},
					s.current.byte_idx - 1,
				}
			}
		}
		return Token{.Dot, {}, s.current.byte_idx}
	case .Greater:
		if s.peek.ty == .Equal {
			tok := Token{.GreaterEqual, {}, s.current.byte_idx}
			advance(s)
			return tok
		} else {
			return Token{.Greater, {}, s.current.byte_idx}
		}
	case .Less:
		if s.peek.ty == .Equal {
			tok := Token{.LessEqual, {}, s.current.byte_idx}
			advance(s)
			return tok
		} else {
			return Token{.Less, {}, s.current.byte_idx}
		}
	case .Bang:
		if s.peek.ty == .Equal {
			tok := Token{.NotEqual, {}, s.current.byte_idx}
			advance(s)
			return tok
		} else {
			return Token{.Not, {}, s.current.byte_idx}
		}
	}
	return Token{.Error, {str = s.source[s.current.byte_idx:]}, s.current.byte_idx}
}

tokenize :: proc(
	source: string,
	allocator := context.temp_allocator,
) -> (
	res: []Token,
	err: Maybe(string),
) {
	tokens: [dynamic]Token = make([dynamic]Token, allocator)

	s := Tokenizer {
		source             = source,
		string_brace_depth = min(int),
	}
	advance(&s)
	for {
		if s.peek.size == 0 {break}
		advance(&s)
		token := read_token(&s)
		if token.ty == .Error {
			return res, token.val.str
		} else if token.ty == .Eof {
			break
		}
		append(&tokens, token)
	}
	return tokens[:], nil

}


CharType :: enum u8 {
	Letter, // default
	Numeric,
	WhiteSpace,
	Comma,
	LeftBrace,
	RightBrace,
	LeftBracket,
	RightBracket,
	LeftParen,
	RightParen,
	Dot,
	Pipe,
	Minus,
	Plus,
	Colon,
	Slash,
	Bang,
	Equal,
	Greater,
	Less,
	DoubleQuote,
}
char_type :: proc "contextless" (ch: rune) -> CharType {
	if ch <= 1 << 7 - 1 {
		return CHAR_TYPES[u8(ch)]
	} else {
		return .Letter
	}
}
CHAR_TYPES: [256]CharType = char_types()
char_types :: proc() -> (table: [256]CharType) {
	set :: proc(table: ^[256]CharType, s: string, c: CharType) {
		for ch in s {
			assert(utf8.rune_size(ch) == 1)
			table[u8(ch)] = c
		}
	}
	set(&table, "0123456789", .Numeric)
	set(&table, " \t\v\n\r", .WhiteSpace)
	set(&table, ",;", .Comma)
	set(&table, "{", .LeftBrace)
	set(&table, "}", .RightBrace)
	set(&table, "[", .LeftBracket)
	set(&table, "]", .RightBracket)
	set(&table, "(", .LeftParen)
	set(&table, ")", .RightParen)
	set(&table, ")", .RightParen)
	set(&table, ".", .Dot)
	set(&table, "|", .Pipe)
	set(&table, "/", .Slash)
	set(&table, "-", .Minus)
	set(&table, "+", .Plus)
	set(&table, ":", .Colon)
	set(&table, "!", .Bang)
	set(&table, "=", .Equal)
	set(&table, ">", .Greater)
	set(&table, "<", .Less)
	set(&table, "\"", .DoubleQuote)

	return table
}
