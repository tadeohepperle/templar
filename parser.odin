package templar

import "base:runtime"
import "core:fmt"

Module :: struct {
	decls: map[string]Decl,
}

Stmt :: struct {
	sep_before: bool, // if true, is appended to output without checking that a space is between them
	kind:       StmtKind,
}
StmtKind :: union #no_nil {
	Ident,
	StrLiteral,
	BoolLiteral,
	IntLiteral,
	Call,
	Block,
	IfStmt,
	Decl,
	Logical,
	LogicalNot,
	ReturnStmt,
	TodoStmt,
	CapitalizeStmt,
	SwitchStmt,
}
Block :: struct {
	statements: []Stmt,
}
CapitalizeStmt :: struct {}
ReturnStmt :: struct {}
TodoStmt :: struct {}
Ident :: struct {
	ident:  string,
	is_arg: bool,
}
StrLiteral :: struct {
	str: string,
}
BoolLiteral :: struct {
	is_true: bool,
}
IntLiteral :: struct {
	number: int,
}
Call :: struct {
	ident: string,
	args:  []Stmt,
}
Decl :: struct {
	ident: string,
	args:  []DeclArg,
	value: ^Stmt,
}
DeclArg :: struct {
	name: string,
	type: Type,
}
Type :: enum {
	Any,
	String,
	Int,
	Bool,
	None,
}

Logical :: struct {
	a:  ^Stmt,
	b:  ^Stmt,
	op: LogicalOp,
}
LogicalOp :: enum {
	And,
	Or,
	Equal,
	NotEqual,
	Less,
	Greater,
	LessEqual,
	GreaterEqual,
}

And :: struct {
	a: ^Stmt,
	b: ^Stmt,
}
Or :: struct {
	a: ^Stmt,
	b: ^Stmt,
}
LogicalNot :: struct {
	inner: ^Stmt,
}
IfStmt :: struct {
	condition: ^Stmt,
	body:      ^Stmt,
	else_body: Maybe(^Stmt),
}

SwitchStmt :: struct {
	condition: ^Stmt,
	cases:     []SwitchCase,
	else_body: Maybe(^Stmt),
}
SwitchCase :: struct {
	val:  Value,
	body: Stmt,
}

drop_module :: proc(mod: ^Module) {
	for ident, &decl in mod.decls {
		delete(decl.args)
		drop_stmt(decl.value)
		free(decl.value)
	}
	delete(mod.decls)
}
drop_stmt :: proc(stmt: ^Stmt) {
	switch s in stmt.kind {
	case CapitalizeStmt:
	case Ident:
	case StrLiteral:
	case BoolLiteral:
	case IntLiteral:
	case ReturnStmt:
	case TodoStmt:
	case LogicalNot:
		drop_stmt(s.inner)
		free(s.inner)
	case Call:
		for &a in s.args {
			drop_stmt(&a)
		}
		delete(s.args)
	case Block:
		for &child in s.statements {
			drop_stmt(&child)
		}
		delete(s.statements)
	case Decl:
		delete(s.args)
		drop_stmt(s.value)
		free(s.value)
	case Logical:
		drop_stmt(s.a)
		free(s.a)
		drop_stmt(s.b)
		free(s.b)
	case IfStmt:
		drop_stmt(s.condition)
		free(s.condition)
		drop_stmt(s.body)
		free(s.body)
		if else_body, ok := s.else_body.(^Stmt); ok {
			drop_stmt(else_body)
			free(else_body)
		}
	case SwitchStmt:
		drop_stmt(s.condition)
		free(s.condition)
		for &ca in s.cases {
			drop_stmt(&ca.body)
		}
		delete(s.cases)
		if else_body, ok := s.else_body.(^Stmt); ok {
			drop_stmt(else_body)
			free(else_body)
		}
	}
}

Error :: Maybe(string)
parse_module :: proc(tokens: []Token, allocator: runtime.Allocator) -> (mod: Module, err: Error) {
	tokens := tokens
	parser := Parser{&tokens, make([dynamic]map[string]None, context.allocator), false}
	defer {
		for env in parser.env_stack {
			delete(env)
		}
		delete(parser.env_stack)
	}
	{
		// parsing code uses the explicitly specified allocator:
		context.allocator = allocator
		mod.decls = make(map[string]Decl, allocator)
		defer if err != nil {
			drop_module(&mod)
		}
		for len(tokens) > 0 {
			stmt := parse_stmt(&parser) or_return
			if decl, ok := stmt.kind.(Decl); ok {
				mod.decls[decl.ident] = decl
			} else {
				err_str := fmt.tprint("top level scope only allows decls, got:", stmt)
				return {}, err_str
			}

		}
	}
	return mod, nil
}

eat :: proc "contextless" (tokens: ^[]Token) -> (tok: Token, ok: bool) {
	if len(tokens) == 0 {
		return {}, false
	}
	tok = tokens[0]
	tokens^ = tokens[1:]
	assert_contextless(tok.ty != .Error)
	if tok.ty == .Eof {
		return {}, false
	}
	return tok, true
}


expect_ident :: proc(tokens: ^[]Token) -> (ident: string, ok: bool) {
	if len(tokens) == 0 {
		return {}, false
	}
	tok := tokens[0]
	if tok.ty == .Ident {
		tokens^ = tokens[1:]
		return tok.val.str, true
	}
	return {}, false
}

accept :: proc "contextless" (tokens: ^[]Token, wanted_ty: TokenTy) -> (ok: bool) {
	if len(tokens) == 0 {
		return false
	}
	if tokens[0].ty == wanted_ty {
		tokens^ = tokens[1:]
		return true
	} else {
		return false
	}
}


parse_stmt :: parse_fmt_string


token_is_connected_to_prev :: proc "contextless" (ty: TokenTy) -> bool {
	#partial switch ty {
	case .StringCurlyStart, .Plus, .StringCurlyStartAndEnd:
		return true
	}
	return false
}

parse_fmt_string :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_or(parser) or_return

	// try to stitch together statements
	if len(tokens) == 0 {
		return stmt, nil
	}
	if _, ok := stmt.kind.(StrLiteral); ok && parser.next_stmt_no_sep_before {
		statements := make([dynamic]Stmt)
		defer if err != nil {
			for &s in statements {
				drop_stmt(&s)
			}
			delete(statements)
		}

		append(&statements, stmt)
		for {
			other := parse_or(parser) or_return
			append(&statements, other)

			if len(tokens) > 0 {
				if _, ok := other.kind.(StrLiteral); ok && parser.next_stmt_no_sep_before {
					continue
				}
				next_ty := tokens[0].ty
				if next_ty == .StringCurlyStart || next_ty == .StringCurlyStartAndEnd {
					continue
				}
			}

			break
		}
		stmt.kind = Block{statements[:]}
	}
	return stmt, nil
}
parse_or :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_and(parser) or_return
	if accept(tokens, .Or) {
		other := parse_and(parser) or_return
		stmt.kind = Logical{new_clone(stmt), new_clone(other), .Or}
	}
	return stmt, nil
}
parse_and :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_cmp(parser) or_return
	if accept(tokens, .And) {
		other := parse_cmp(parser) or_return
		stmt.kind = Logical{new_clone(stmt), new_clone(other), .And}
	}
	return stmt, nil
}
parse_cmp :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_single(parser) or_return


	TokenAndOp :: struct {
		ty: TokenTy,
		op: LogicalOp,
	}
	TABLE :: [?]TokenAndOp {
		{.NotEqual, .NotEqual},
		{.EqualEqual, .Equal},
		{.Greater, .Greater},
		{.Less, .Less},
		{.GreaterEqual, .GreaterEqual},
		{.LessEqual, .LessEqual},
	}
	for t in TABLE {
		if accept(tokens, t.ty) {
			other := parse_single(parser) or_return
			stmt.kind = Logical{new_clone(stmt), new_clone(other), t.op}
			break
		}
	}
	return stmt, nil
}


Parser :: struct {
	tokens:                  ^[]Token,
	env_stack:               [dynamic]map[string]None,
	next_stmt_no_sep_before: bool,
}
None :: struct {}

parse_single :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt.sep_before = !accept(tokens, .Plus)
	if parser.next_stmt_no_sep_before {
		stmt.sep_before = false
		parser.next_stmt_no_sep_before = false
	}
	is_not := accept(tokens, .Not)
	defer if is_not && err == nil {
		stmt.kind = LogicalNot{new_clone(stmt)}
	}

	tok, ok := eat(tokens)
	if !ok {
		return {}, "no tokens left to start statement"
	}
	#partial switch tok.ty {
	case .String, .StringCurlyStart, .StringCurlyEnd, .StringCurlyStartAndEnd:
		// when curly start: no seperator between the content of pocket and the following part of string
		if tok.ty == .StringCurlyStart || tok.ty == .StringCurlyStartAndEnd {
			stmt.sep_before = false
		}
		// when curly end: no seperator between the content and the part of the string before:
		if tok.ty == .StringCurlyEnd || tok.ty == .StringCurlyStartAndEnd {
			parser.next_stmt_no_sep_before = true
		}
		stmt.kind = StrLiteral{tok.val.str}
		return
	case .Number:
		stmt.kind = IntLiteral {
			number = tok.val.number,
		}
		return
	case .Return:
		stmt.kind = ReturnStmt{}
		return
	case .Todo:
		stmt.kind = TodoStmt{}
		return
	case .Capitalize:
		stmt.kind = CapitalizeStmt{}
		return
	case .Ident:
		ident := tok.val.str
		if accept(tokens, .Equal) {
			// parse foo = ... statement
			value := parse_stmt(parser) or_return
			stmt.kind = Decl {
				ident = ident,
				args  = nil,
				value = new_clone(value),
			}
			return
		} else if accept(tokens, .LeftParen) {
			if tok_behind, ok := token_behind_next_closing_paren(tokens^);
			   ok && tok_behind == .Equal {
				// expect function definition
				decl_args := make([dynamic]DeclArg)
				env := make(map[string]None)
				for {
					if accept(tokens, .RightParen) {
						break
					}
					ident, is_ident := expect_ident(tokens)
					if !is_ident {
						delete(decl_args)
						delete(env)
						return {}, "expected ident in function declaration!"
					}
					decl_arg := DeclArg{ident, .Any}

					if accept(tokens, .Colon) {
						if accept(tokens, .IntType) {
							decl_arg.type = .Int
						} else if accept(tokens, .BoolType) {
							decl_arg.type = .Bool
						} else if accept(tokens, .StringType) {
							decl_arg.type = .String
						} else {
							delete(decl_args)
							delete(env)
							return {}, "invalid type after colon, expected `bool` or `int`"
						}
					}

					append(&decl_args, decl_arg)
					env[ident] = None{}
				}
				if len(decl_args) == 0 {
					delete(decl_args)
					delete(env)
					return {}, "zero args in function declaration"
				}

				append(&parser.env_stack, env)
				defer {
					env := pop(&parser.env_stack)
					delete(env)
				}
				assert(accept(tokens, .Equal))
				value := parse_stmt(parser) or_return
				stmt.kind = Decl{ident, decl_args[:], new_clone(value)}
				return
			} else {
				// expect function call
				args := parse_stmts_until(parser, .RightParen) or_return
				if len(args) == 0 {
					delete(args)
					return {}, "zero args in function call"
				}
				stmt.kind = Call{ident, args}
				return
			}
		} else {
			// just single ident expression
			is_arg := false
			if len(env_stack) > 0 {
				cur_env := env_stack[len(env_stack) - 1]
				is_arg = ident in cur_env
			}
			stmt.kind = Ident{ident, is_arg}
			return
		}
	case .If:
		condition := parse_stmt(parser) or_return
		defer if err != nil {
			drop_stmt(&condition)
		}
		// pass the no_sep_before flag to first child instead:
		if !stmt.sep_before do parser.next_stmt_no_sep_before = true
		body := parse_stmt(parser) or_return
		if accept(tokens, .Else) {
			defer if err != nil {
				drop_stmt(&body)
			}
			// pass the no_sep_before to the else branch as well:
			if !stmt.sep_before do parser.next_stmt_no_sep_before = true
			else_body := parse_stmt(parser) or_return
			stmt.kind = IfStmt{new_clone(condition), new_clone(body), new_clone(else_body)}
			return
		} else {
			stmt.kind = IfStmt{new_clone(condition), new_clone(body), nil}
			return
		}
	case .Switch:
		condition := parse_stmt(parser) or_return
		defer if err != nil {
			drop_stmt(&condition)
		}
		if !accept(tokens, .LeftBrace) {
			return {}, "expected `{` after condition of switch statement"
		}
		switch_cases := make([dynamic]SwitchCase)
		defer if err != nil {
			for &ca in switch_cases {
				drop_stmt(&ca.body)
			}
			delete(switch_cases)
		}
		for {
			if len(tokens) == 0 {
				return {}, "switch statement was not closed with `}`"
			}
			if accept(tokens, .RightBrace) {
				break
			}
			val := expect_const_value(parser) or_return
			if !accept(tokens, .Colon) {
				return {}, "expected `:` after condition of switch statement"
			}
			// pass the no_sep_before to every individual case
			if !stmt.sep_before do parser.next_stmt_no_sep_before = true
			body := parse_stmt(parser) or_return
			append(&switch_cases, SwitchCase{val, body})
		}
		else_body: Maybe(^Stmt) = nil
		if accept(tokens, .Else) {
			// pass the no_sep_before to the else branch as well:
			if !stmt.sep_before do parser.next_stmt_no_sep_before = true
			else_b := parse_stmt(parser) or_return
			else_body = new_clone(else_b)
		}
		stmt.kind = SwitchStmt{new_clone(condition), switch_cases[:], else_body}
		return
	case .LeftBrace:
		if !stmt.sep_before {
			parser.next_stmt_no_sep_before = true
		}
		statements := parse_stmts_until(parser, .RightBrace) or_return
		stmt.kind = Block{statements}
		return
	case .LeftBracket:
		// for lookup tables e.g. ["HELLO" = "hallo", "WHATSUP" = "wie geht's?"]
		unimplemented()
	}
	return {}, tprint("invalid start of expression", tok)
}

expect_const_value :: proc(using parser: ^Parser) -> (val: Value, err: Error) {
	tok, ok := eat(tokens)
	if !ok {
		return {}, "no tokens left to start const value"
	}
	#partial switch tok.ty {
	case .Number:
		return Value(tok.number), nil
	case .String:
		return Value(tok.str), nil
	}
	return {}, tprint("invalid token for const value: ", tok)
}

token_behind_next_closing_paren :: proc(tokens: []Token) -> (token_ty: TokenTy, ok: bool) {
	stack := make([dynamic]TokenTy, context.temp_allocator)
	for t, idx in tokens {
		#partial switch t.ty {
		case .LeftBrace:
			append(&stack, TokenTy.RightBrace)
		case .LeftBracket:
			append(&stack, TokenTy.RightBracket)
		case .LeftParen:
			append(&stack, TokenTy.RightParen)
		}
		if len(stack) > 0 {
			if t.ty == stack[len(stack) - 1] {
				pop(&stack)
			}
		} else if t.ty == .RightParen {
			if idx + 1 < len(tokens) {
				return tokens[idx + 1].ty, true
			}
			break
		}
	}
	return .Eof, false
}

// // also skips over the last token
parse_stmts_until :: proc(using parser: ^Parser, until: TokenTy) -> (stmts: []Stmt, err: Error) {
	arr := make([dynamic]Stmt)
	defer if err != nil {
		for &stmt in arr {
			drop_stmt(&stmt)
		}
		delete(arr)
	}
	for {
		if accept(tokens, until) {
			break
		}
		stmt := parse_stmt(parser) or_return
		append(&arr, stmt)
	}
	return arr[:], nil

}


/*

roman(3)

roman(2)


*/
