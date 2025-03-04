package templar

import "base:runtime"
import "core:fmt"

Module :: struct {
	decls: map[string]Decl,
}
Stmt :: union #no_nil {
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
}
Block :: struct {
	statements: []Stmt,
}
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
	Eq,
	NotEq,
	And,
	Or,
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
// Logical :: struct {
//     op: 
// }
IfStmt :: struct {
	condition: ^Stmt,
	body:      ^Stmt,
	else_body: Maybe(^Stmt),
}

drop_module :: proc(mod: ^Module, allocator := context.allocator) {
	for ident, &decl in mod.decls {
		delete(decl.args)
		drop_stmt(decl.value, allocator)
	}
}
drop_stmt :: proc(stmt: ^Stmt, allocator := context.allocator) {
	switch s in stmt {
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
			drop_stmt(&a, allocator)
		}
		delete(s.args)
	case Block:
		delete(s.statements)
	case Decl:
		delete(s.args)
		drop_stmt(s.value, allocator)
		free(s.value)
	case Logical:
		drop_stmt(s.a, allocator)
		free(s.a)
		drop_stmt(s.b, allocator)
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

	}
}

Error :: Maybe(string)
parse_module :: proc(tokens: []Token, allocator: runtime.Allocator) -> (mod: Module, err: Error) {
	tokens := tokens
	parser := Parser{&tokens, allocator, nil}
	mod.decls = make(map[string]Decl, allocator)
	defer if err != nil {
		drop_module(&mod)
		for env in parser.env_stack {
			delete(env)
		}
		delete(parser.env_stack)
	}


	for len(tokens) > 0 {
		stmt := parse_stmt(&parser) or_return
		if decl, ok := stmt.(Decl); ok {
			mod.decls[decl.ident] = decl
		} else {
			err_str := fmt.tprint("top level scope only allows decls, got:", stmt)
			return {}, err_str
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


parse_stmt :: parse_or
parse_or :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_and(parser) or_return
	if accept(tokens, .Or) {
		other := parse_and(parser) or_return
		return Logical{new_clone(stmt, allocator), new_clone(other, allocator), .Or}, nil
	}
	return stmt, nil
}
parse_and :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_cmp(parser) or_return
	if accept(tokens, .And) {
		other := parse_cmp(parser) or_return
		return Logical{new_clone(stmt, allocator), new_clone(other, allocator), .And}, nil
	}
	return stmt, nil
}
parse_cmp :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	stmt = parse_single(parser) or_return
	if accept(tokens, .EqualEqual) {
		other := parse_single(parser) or_return
		return Logical{new_clone(stmt, allocator), new_clone(other, allocator), .Eq}, nil
	} else if accept(tokens, .NotEqual) {
		other := parse_single(parser) or_return
		return Logical{new_clone(stmt, allocator), new_clone(other, allocator), .NotEq}, nil
	}
	return stmt, nil
}


Parser :: struct {
	tokens:    ^[]Token,
	allocator: runtime.Allocator,
	env_stack: [dynamic]map[string]None,
}
None :: struct {}

parse_single :: proc(using parser: ^Parser) -> (stmt: Stmt, err: Error) {
	is_not := accept(tokens, .Not)
	defer if is_not && err == nil {
		stmt = LogicalNot{new_clone(stmt, allocator)}
	}

	tok, ok := eat(tokens)
	if !ok {
		return {}, "no tokens left to start statement"
	}
	#partial switch tok.ty {
	case .String:
		return StrLiteral{str = tok.val.str}, nil
	case .Number:
		return IntLiteral{number = tok.val.number}, nil
	case .Return:
		return ReturnStmt{}, nil
	case .Todo:
		return TodoStmt{}, nil
	case .Ident:
		ident := tok.val.str
		if accept(tokens, .Equal) {
			// parse foo = ... statement
			value := parse_single(parser) or_return
			return Decl{ident = ident, args = nil, value = new_clone(value, allocator)}, nil
		} else if accept(tokens, .LeftParen) {
			if tok_behind, ok := token_behind_next_closing_paren(tokens^);
			   ok && tok_behind == .Equal {
				// expect function definition
				decl_args := make([dynamic]DeclArg, allocator)
				env := make(map[string]None, allocator)
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
				return Decl{ident, decl_args[:], new_clone(value)}, nil
			} else {
				// expect function call
				args := parse_stmts_until(parser, .RightParen) or_return
				if len(args) == 0 {
					return {}, "zero args in function call"
				}
				return Call{ident, args}, nil
			}


			// args := parse_stmts_until(tokens, .RightParen, allocator) or_return
			// if len(args) == 0 {
			// 	return {}, "zero args in function def/call"
			// }
			// if accept(tokens, .Equal) {
			// 	// expect a fn def, where all arg names are idents: foo(one, bar, world) = ...
			// 	arg_names := make([]Ident, len(args), allocator)
			// 	for a, idx in args {
			// 		if ident, ok := a.(Ident); ok {
			// 			arg_names[idx] = ident
			// 		} else {
			// 			delete(args, allocator)
			// 			delete(arg_names, allocator)
			// 			return stmt, fmt.tprint("arg names should be idents in fn def, got:", a)
			// 		}
			// 	}
			// 	value := parse_single(tokens, allocator) or_return
			// 	return Decl{ident, arg_names, new_clone(value, allocator)}, nil
			// } else {
			// 	// this is a function call. e.g. foo("Hello", bar, world)
			// 	return Call{ident, args}, nil
			// }
		} else {
			// just single ident expression
			is_arg := false
			if len(env_stack) > 0 {
				cur_env := env_stack[len(env_stack) - 1]
				is_arg = ident in cur_env
			}
			return Ident{ident, is_arg}, nil
		}
	case .If:
		condition := parse_stmt(parser) or_return
		defer if err != nil {
			drop_stmt(&condition)
		}
		body := parse_stmt(parser) or_return
		if accept(tokens, .Else) {
			defer if err != nil {
				drop_stmt(&body)
			}
			else_body := parse_stmt(parser) or_return
			return IfStmt{new_clone(condition), new_clone(body), new_clone(else_body)}, nil
		} else {
			return IfStmt{new_clone(condition), new_clone(body), nil}, nil
		}
	case .LeftBrace:
		statements := parse_stmts_until(parser, .RightBrace) or_return
		return Block{statements}, nil
	case .LeftBracket:
		// for lookup tables e.g. ["HELLO" = "hallo", "WHATSUP" = "wie geht's?"]
		unimplemented()
	}
	return {}, "invalid start of expression"
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
	arr := make([dynamic]Stmt, allocator)
	defer if err != nil {
		delete(arr)
	}
	stmt_loop: for {
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
