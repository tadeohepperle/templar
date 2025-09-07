package templar

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Builder :: strings.Builder
builder :: proc(allocator := context.temp_allocator) -> (b: Builder) {
	strings.builder_init(&b, allocator)
	return b
}

write :: #force_inline proc(b: ^Builder, s: string) {
	append(&b.buf, s)
}
tprint :: fmt.tprint
Value :: union {
	string,
	int,
	bool,
}
value_to_ty :: proc "contextless" (val: Value) -> Type {
	switch val in val {
	case string:
		return .String
	case int:
		return .Int
	case bool:
		return .Bool
	}
	return .None
}

run :: proc(
	source: string,
	decl_name: string,
	arg_values: []Value,
	allocator := context.temp_allocator,
) -> (
	res: string,
	err: Error,
) {
	tokens := tokenize(source) or_return
	// for tok in tokens {
	// 	print(tok)
	// 	#partial switch tok.ty {
	// 	case .Ident:
	// 		print("   ", tok.str)
	// 	case .String:
	// 		print("   ", tok.str)
	// 		print("   ", len(tok.str))
	// 	case .Number:
	// 		print("   ", tok.number)
	// 	}
	// }
	mod := parse_module(tokens, context.allocator) or_return
	defer {
		drop_module(&mod)
	}
	builder := builder(allocator)
	res = execute(mod, decl_name, arg_values, &builder) or_return
	return res, nil
}

run_and_show :: proc(source: string, decl_name: string, arg_values: ..Value) {
	res, err := run(source, decl_name, arg_values)
	if err, is_err := err.(string); is_err {
		print("ERROR:")
		print(err)
	} else {
		print("SUCCESS:")
		print(res)
	}
}

execute :: proc(
	module: Module,
	decl_name: string,
	arg_values: []Value,
	builder: ^strings.Builder,
) -> (
	res: string,
	err: Error,
) {
	assert(builder != nil)
	if decl, ok := module.decls[decl_name]; ok {
		// shortcut for simple key value declarations:
		if str_literal, ok := decl.value.kind.(StrLiteral); ok {
			return str_literal.str, nil
		}
		env := env_for_values(arg_values, decl.args) or_return
		ctx := ExecutionCtx{module, env, builder, false, false}
		defer if err != nil {
			delete(ctx.b.buf)
		}
		err := _execute_stmt(&ctx, decl.value^)
		if err, is_err := err.(string); is_err {
			return {}, err
		}
		return strings.to_string(ctx.b^), nil
	} else {
		return {}, tprint("ERROR(", decl_name, " is undefined)", sep = "")
	}
}
Env :: map[string]Value
// returns env in tmp storage
env_for_values :: proc(values: []Value, decl_args: []DeclArg) -> (env: Env, err: Error) {
	env = make(Env, context.temp_allocator)
	if len(values) != len(decl_args) {
		return nil, tprint("number of args is wrong, given:", values, "expected:", decl_args)
	}
	for val, idx in values {
		decl_arg := decl_args[idx]
		if decl_arg.type != .Any && value_to_ty(val) != decl_arg.type {
			return nil, tprint("value", val, "has wrong type for", decl_arg)
		}
		env[decl_arg.name] = val
	}
	return env, nil
}

ErrorOrReturn :: union {
	Return,
	string,
}
Return :: struct {}


ExecutionCtx :: struct {
	module:          Module,
	env:             Env,
	b:               ^Builder,
	no_sep_before:   bool,
	capitalize_next: bool,
}


_ctx_write_value :: #force_inline proc(ctx: ^ExecutionCtx, val: Value) {
	if !ctx.no_sep_before {
		if len(ctx.b.buf) > 0 && ctx.b.buf[len(ctx.b.buf) - 1] != ' ' {
			append(&ctx.b.buf, ' ')
		}
	} else {
		ctx.no_sep_before = false
	}
	switch val in val {
	case string:
		if ctx.capitalize_next {
			ru, ru_size := utf8.decode_rune(val)
			if ru_size > 0 {
				ru_upper := unicode.to_upper(ru)
				strings.write_rune(ctx.b, ru_upper) // first character in uppercase
				write(ctx.b, val[ru_size:]) // rest of string
			}
		} else {
			write(ctx.b, val)
		}
	case int:
		fmt.sbprint(ctx.b, val)
	case bool:
		fmt.sbprint(ctx.b, val)
	}
	ctx.capitalize_next = false
}
_execute_stmt :: proc(using ctx: ^ExecutionCtx, stmt: Stmt) -> ErrorOrReturn {
	if ctx.no_sep_before || !stmt.sep_before {
		ctx.no_sep_before = true
	}
	switch this in stmt.kind {
	case CapitalizeStmt:
		ctx.capitalize_next = true
	case Ident:
		if this.is_arg {
			val, ok := env[this.ident]
			if !ok {
				return tprint("No arg named", this.ident)
			}
			_ctx_write_value(ctx, val)
		} else {
			decl, ok := module.decls[this.ident]
			if !ok {
				print("EXECUTE IDENT", this)
				return tprint("No declaration named", this.ident)
			}
			if len(decl.args) > 0 {
				return tprint("ident refers to decl", this.ident, "but is used with no args")
			}
			return _execute_stmt(ctx, decl.value^) // redirect to the other def
		}
	case StrLiteral:
		_ctx_write_value(ctx, this.str)
	case BoolLiteral:
		_ctx_write_value(ctx, this.is_true)
	case IntLiteral:
		_ctx_write_value(ctx, this.number)
	case Call:
		decl, ok := module.decls[this.ident]
		if !ok {
			return tprint("No declaration named", this.ident)
		}
		if len(decl.args) == 0 {
			return tprint("call expression should have 1 or more args")
		}
		if len(decl.args) != len(this.args) {
			return tprint("invalid number of arguments, expected:", decl.args, ", got:", this.args)
		}
		call_env := make(Env, context.temp_allocator)
		for decl_arg, idx in decl.args {
			call_arg := this.args[idx]
			call_arg_val, call_arg_eval_err := _evaluate_stmt(module, call_arg, env)
			if err, is_err := call_arg_eval_err.(string); is_err {
				return err
			}
			if decl_arg.type != .Any && value_to_ty(call_arg_val) != decl_arg.type {
				return tprint("value", call_arg_val, "has wrong type for arg", decl_arg)
			}
			call_env[decl_arg.name] = call_arg_val
		}
		call_ctx := ExecutionCtx {
			module        = ctx.module,
			env           = call_env,
			b             = ctx.b,
			no_sep_before = ctx.no_sep_before,
		}
		call_res := _execute_stmt(&call_ctx, decl.value^)
		ctx.b = call_ctx.b
		// check for err or Return{}, ignore Return{}, because we don't want an inner return to bubble up through calling parent functions...
		if call_err, has_err := call_res.(string); has_err {
			return call_err
		}
		return nil
	case Block:
		for child in this.statements {
			_execute_stmt(ctx, child) or_return
		}
	case IfStmt:
		cond_val, cond_val_err := _evaluate_stmt(module, this.condition^, env)
		if err, has_err := cond_val_err.(string); has_err {
			return err
		}
		cond_val_is_true, is_bool := cond_val.(bool)
		if !is_bool {
			return tprint("condition for if-statement needs to be bool, got: ", cond_val)
		}
		if cond_val_is_true {
			_execute_stmt(ctx, this.body^) or_return
		} else if else_body, has_else := this.else_body.(^Stmt); has_else {
			_execute_stmt(ctx, else_body^) or_return
		}
		return nil
	case SwitchStmt:
		cond_val, cond_val_err := _evaluate_stmt(module, this.condition^, env)
		if err, has_err := cond_val_err.(string); has_err {
			return err
		}
		found_case := false
		for ca in this.cases {
			if cond_val == ca.val {
				_execute_stmt(ctx, ca.body) or_return
				found_case = true
				break
			}
		}
		if else_body, has_else := this.else_body.(^Stmt); has_else && !found_case {
			_execute_stmt(ctx, else_body^) or_return
		}
		return nil
	case Decl:
		return nil
	case Logical:
		return nil
	case LogicalNot:
		return nil
	case ReturnStmt:
		return Return{}
	case TodoStmt:
		return "todo, not implemented!"
	}
	return nil
}

_write_value :: proc(val: Value, b: ^Builder) {
	switch val in val {
	case string:
		write(b, val)
	case int:
		fmt.sbprint(b, val)
	case bool:
		fmt.sbprint(b, val)
	}
}

_evaluate_stmt :: proc(module: Module, stmt: Stmt, env: Env) -> (val: Value, err: Error) {
	switch this in stmt.kind {
	case CapitalizeStmt:
		return nil, "#cap is not an expression that can be evaluated on its own!"
	case Ident:
		if this.is_arg {
			val, ok := env[this.ident]
			if !ok {
				return nil, tprint("No arg named", this.ident)
			}
			return val, nil
		} else {
			decl, ok := module.decls[this.ident]
			if !ok {
				return nil, tprint("No declaration named", this.ident)
			}
			if len(decl.args) > 0 {
				return nil, tprint("ident refers to decl", this.ident, "but is used with no args")
			}
			return _evaluate_stmt(module, decl.value^, nil) // redirect to the other def
		}
	case StrLiteral:
		return this.str, nil
	case BoolLiteral:
		return this.is_true, nil
	case IntLiteral:
		return this.number, nil
	case Call:
		unimplemented("getting return values from calls not supported yet")
	case Block:
		switch len(this.statements) {
		case 0:
			return nil, nil
		case 1:
			return _evaluate_stmt(module, this.statements[0], env)
		case:
			b := builder(context.temp_allocator)
			ctx := ExecutionCtx{module, env, &b, false, false}
			loop: for child in this.statements {
				switch return_or_err in _execute_stmt(&ctx, child) {
				case Return:
					break loop
				case string:
					return nil, return_or_err
				}
			}
			return strings.to_string(b), nil
		}
	case SwitchStmt:
		unimplemented()
	case IfStmt:
		unimplemented()
	case Decl:
		return nil, "declaration cannot be evaluated"
	case Logical:
		a_val := _evaluate_stmt(module, this.a^, env) or_return
		b_val := _evaluate_stmt(module, this.b^, env) or_return
		op := this.op
		switch op {
		case .And, .Or:
			a_bool, a_is_bool := a_val.(bool)
			b_bool, b_is_bool := b_val.(bool)
			if !a_is_bool || !b_is_bool {
				return nil, tprint(
					"operation",
					op,
					" only accepts boolean values, got:",
					a_val,
					", ",
					b_val,
				)
			}
			if op == .And {
				return a_bool && b_bool, nil
			} else {
				return a_bool || b_bool, nil // todo! could short-circuit here for .Or, no need to evaluate b!
			}
		case .Equal, .NotEqual:
			is_same: bool = a_val == b_val
			if op == .Equal {
				return is_same, nil
			} else {
				return !is_same, nil
			}
		case .Less, .Greater, .LessEqual, .GreaterEqual:
			a_num, a_is_int := a_val.(int)
			b_num, b_is_int := b_val.(int)
			if !a_is_int || !b_is_int {
				return nil, tprint(
					"operation",
					op,
					" only accepts int values, got:",
					a_val,
					", ",
					b_val,
				)
			}
			#partial switch op {
			case .Less:
				return a_num < b_num, nil
			case .Greater:
				return a_num > b_num, nil
			case .LessEqual:
				return a_num <= b_num, nil
			case .GreaterEqual:
				return a_num >= b_num, nil
			}
			unreachable()
		}
		panic("invalid op, should have been handled above")
	case LogicalNot:
		val := _evaluate_stmt(module, this.inner^, env) or_return
		if is_true, ok := val.(bool); ok {
			return !is_true, nil
		} else {
			return nil, "cannot negate non-boolean value"
		}
	case ReturnStmt:
		return nil, "return statement cannot be evaluated"
	case TodoStmt:
		return nil, "todo, not implemented!"
	}
	return nil, nil
}
