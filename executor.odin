package templar

import "core:fmt"
import "core:strings"

Builder :: strings.Builder
builder :: proc(allocator := context.temp_allocator) -> (b: Builder) {
	strings.builder_init(&b, allocator)
	return b
}
write :: strings.write_string
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

run :: proc(source: string, decl_name: string, arg_values: []Value) -> (res: string, err: Error) {
	STR :: `FOO = {"Hello" " World!"}`
	tokens := tokenize(source) or_return
	print(tokens)
	mod := parse_module(tokens, context.allocator) or_return
	res = execute(mod, "FOO", arg_values) or_return
	drop_module(&mod)
	return res, nil
}

execute :: proc(
	module: Module,
	decl_name: string,
	arg_values: []Value,
	allocator := context.temp_allocator,
) -> (
	res: string,
	err: Error,
) {
	if decl, ok := module.decls[decl_name]; ok {
		// shortcut for simple key value declarations:
		if str_literal, ok := decl.value.(StrLiteral); ok {
			return str_literal.str, nil
		}

		b := builder(allocator)
		defer if err != nil {
			delete(b.buf)
		}

		env := env_for_values(arg_values, decl.args) or_return
		err := _execute_stmt(module, decl.value^, env, &b)
		if err, is_err := err.(string); is_err {
			return {}, err
		}
		return strings.to_string(b), nil
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
			return nil, tprint("value", val, "has wrong type for arg", decl_arg)
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


_execute_stmt :: proc(module: Module, stmt: Stmt, env: Env, b: ^Builder) -> ErrorOrReturn {
	switch stmt in stmt {
	case Ident:
		if stmt.is_arg {
			val, ok := env[stmt.ident]
			if !ok {
				return tprint("No arg named", stmt.ident)
			}
			_write_value(val, b)
		} else {
			decl, ok := module.decls[stmt.ident]
			if !ok {
				return tprint("No declaration named", stmt.ident)
			}
			if len(decl.args) > 0 {
				return tprint("ident refers to decl", stmt.ident, "but is used with no args")
			}
			return _execute_stmt(module, decl.value^, nil, b) // redirect to the other def
		}
	case StrLiteral:
		write(b, stmt.str)
	case BoolLiteral:
		fmt.sbprint(b, stmt.is_true)
	case IntLiteral:
		fmt.sbprint(b, stmt.number)
	case Call:
		decl, ok := module.decls[stmt.ident]
		if !ok {
			return tprint("No declaration named", stmt.ident)
		}
		if len(decl.args) == 0 {
			return tprint("call expression should have 1 or more args")
		}
		if len(decl.args) != len(stmt.args) {
			return tprint("invalid number of arguments, expected:", decl.args, ", got:", stmt.args)
		}
		call_env := make(Env, context.temp_allocator)
		for decl_arg, idx in decl.args {
			call_arg := stmt.args[idx]
			call_arg_val, call_arg_eval_err := _evaluate_stmt(module, call_arg, env)
			if err, is_err := call_arg_eval_err.(string); is_err {
				return err
			}
			if value_to_ty(call_arg_val) != decl_arg.type {
				return tprint("value", call_arg_val, "has wrong type for arg", decl_arg)
			}
			call_env[decl_arg.name] = call_arg_val
		}
		call_res := _execute_stmt(module, decl.value^, call_env, b)
		// check for err or Return{}, ignore Return{}, because we don't want an inner return to bubble up through calling parent functions...
		if call_err, has_err := call_res.(string); has_err {
			return call_err
		}
		return nil
	case Block:
		for child in stmt.statements {
			_execute_stmt(module, child, env, b) or_return
		}
	case IfStmt:
		cond_val, cond_val_err := _evaluate_stmt(module, stmt.condition^, env)
		if err, has_err := cond_val_err.(string); has_err {
			return err
		}
		cond_val_is_true, is_bool := cond_val.(bool)
		if !is_bool {
			return tprint("condition for if-statement needs to be bool, got: ", cond_val)
		}
		if cond_val_is_true {
			_execute_stmt(module, stmt.body^, env, b) or_return
		} else if else_body, has_else := stmt.else_body.(^Stmt); has_else {
			_execute_stmt(module, else_body^, env, b) or_return
		}
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
	switch stmt in stmt {
	case Ident:
		if stmt.is_arg {
			val, ok := env[stmt.ident]
			if !ok {
				return nil, tprint("No arg named", stmt.ident)
			}
			return val, nil
		} else {
			decl, ok := module.decls[stmt.ident]
			if !ok {
				return nil, tprint("No declaration named", stmt.ident)
			}
			if len(decl.args) > 0 {
				return nil, tprint("ident refers to decl", stmt.ident, "but is used with no args")
			}
			return _evaluate_stmt(module, decl.value^, nil) // redirect to the other def
		}
	case StrLiteral:
		return stmt.str, nil
	case BoolLiteral:
		return stmt.is_true, nil
	case IntLiteral:
		return stmt.number, nil
	case Call:
		unimplemented("getting return values from calls not supported yet")
	case Block:
		b := builder()
		loop: for child in stmt.statements {
			switch return_or_err in _execute_stmt(module, child, env, &b) {
			case Return:
				break loop
			case string:
				return nil, return_or_err
			}
		}
		return strings.to_string(b), nil
	case IfStmt:
		unimplemented()
	case Decl:
		return nil, "declaration cannot be evaluated"
	case Logical:
		a_val := _evaluate_stmt(module, stmt.a^, env) or_return
		b_val := _evaluate_stmt(module, stmt.b^, env) or_return
		op := stmt.op
		switch op {
		case .And, .Or:
			a_bool, a_is_bool := a_val.(bool)
			b_bool, b_is_bool := a_val.(bool)
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
		case .Eq, .NotEq:
			is_same := a_val == b_val
			if op == .Eq {
				return is_same, nil
			} else {
				return !is_same, nil
			}
		}
		panic("invalid op, should have been handled above")
	case LogicalNot:
		val := _evaluate_stmt(module, stmt, env) or_return
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
