package templar
import "core:strconv"
import "core:unicode/utf8"

Tokenizer :: struct {
	source:  string,
	current: Char,
	peek:    Char,
	line:    int,
	col:     int,
}
Char :: struct {
	ty:       CharType,
	byte_idx: int,
	size:     int,
}
advance :: proc(using this: ^Tokenizer) {
	current = peek
	peek.byte_idx += peek.size
	ch: rune
	ch, peek.size = utf8.decode_rune(source[peek.byte_idx:])
	peek.ty = char_type(ch)
}

Token :: struct {
	ty:        TokenTy,
	using val: struct #raw_union {
		str:    string,
		number: int,
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
	String,
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
		start_byte := s.current.byte_idx
		for s.peek.ty != .DoubleQuote {
			advance(s)
		}
		string_content := s.source[start_byte + 1:s.peek.byte_idx]
		token := Token{.String, {str = string_content}, start_byte}
		advance(s) // skip over last doublequote
		return token
	case .Colon:
		return Token{.Colon, {}, s.current.byte_idx}
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
	case .LeftBrace:
		return Token{.LeftBrace, {}, s.current.byte_idx}
	case .RightBrace:
		return Token{.RightBrace, {}, s.current.byte_idx}
	case .LeftBracket:
		return Token{.LeftBracket, {}, s.current.byte_idx}
	case .RightBracket:
		return Token{.RightBracket, {}, s.current.byte_idx}
	case .LeftParen:
		return Token{.LeftParen, {}, s.current.byte_idx}
	case .RightParen:
		return Token{.RightParen, {}, s.current.byte_idx}
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
		source = source,
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
