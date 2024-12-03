/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package hscript;

import hscript.Expr;

class Printer {

	var buf : StringBuf;
	var tabs : String;

	public function new() {
	}

	public function exprToString( e : Expr ) {
		buf = new StringBuf();
		tabs = "";
		expr(e);
		return buf.toString();
	}

	public function typeToString( t : CType ) {
		buf = new StringBuf();
		tabs = "";
		type(t);
		return buf.toString();
	}

	inline function add<T>(s:T) buf.add(s);

	function type( t : CType ) {
		switch( t ) {
			case CTOpt(t):
				add('?'); type(t);
			case CTPath(path, params):
				add(path.join("."));
				if( params != null ) {
					add("<");
					var first = true;
					for( p in params ) {
						if( first ) first = false else add(", ");
						type(p);
					}
					add(">");
				}
			case CTNamed(name, t):
				add(name); add(':'); type(t);
			case CTFun(args, ret) if (Lambda.exists(args, function (a) return a.match(CTNamed(_, _)))):
				add('(');
				for (a in args)
					switch a {
						case CTNamed(_, _): type(a);
						default: type(CTNamed('_', a));
					}
				add(')->');
				type(ret);
			case CTFun(args, ret):
				if( args.length == 0 )
					add("Void -> ");
				else {
					for( a in args ) {
						type(a);
						add(" -> ");
					}
				}
				type(ret);
			case CTAnon(fields):
				add("{");
				var first = true;
				for( f in fields ) {
					if( first ) { first = false; add(" "); } else add(", ");
					add(f.name + " : ");
					type(f.t);
				}
				add(first ? "}" : " }");
			case CTParent(t):
				add("("); type(t); add(")");
		}
	}

	function addType( t : CType ) {
		if( t != null ) {
			add(":");
			type(t);
		}
	}

	function expr( e : Expr ) {
		if( e == null ) {
			add("??NULL??");
			return;
		}
		switch (Tools.expr(e))  {
			case EUsing(c):
				add("using " + c);
			case EImportStar(c):
				add("import " + c + "*");
			case EImport(c, n):
				add("import " + c);
				if(n != null)
					add(' as $n');
			case EClass(name, fields, extend, interfaces):
				add('class $name');
				if (extend != null)
					add(' extends $extend');
				for(_interface in interfaces) {
					add(' implements $_interface');
				}
				add(' {\n');
				tabs += "\t";
				for(field in fields) {
					add(tabs);
					expr(field);
					add(";\n");
				}

				tabs = tabs.substring(1);
				add(tabs);
				add("}");
			case EConst(c):
				switch( c ) {
					case CInt(i): add(i);
					case CFloat(f): add(f);
					case CString(s): add('"'); add(s.split('"').join('\\"').split("\n").join("\\n").split("\r").join("\\r").split("\t").join("\\t")); add('"');
				}
			case EIdent(v):
				add(v);
			case EVar(n, t, e, a):
				if (a != null)
				{
					var aStr = Std.string(a);
					add(aStr);
					if (aStr.length > 0)
						add(" ");
				}
				add(a.isFinal ? "final " : "var ");
				add(n);
				addType(t);
				if( e != null ) {
					add(" = ");
					expr(e);
				}
			case EParent(e):
				add("("); expr(e); add(")");
			case EBlock(el):
				if( el.length == 0 ) {
					add("{}");
				} else {
					tabs += "\t";
					add("{\n");
					for( e in el ) {
						add(tabs);
						expr(e);
						// switch Tools.expr(e)
						// {
						// 	case EWhile(_, _) | EDoWhile(_, _) | EFor(_, _, _) | EIf(_, _):
						// 	default:
								add(";");
						// }
						add("\n");
					}
					tabs = tabs.substring(1);
					add(tabs);
					add("}");
				}
			case EField(e, f, s):
				expr(e);
				add((s == true ? "?." : ".") + f);
			case EBinop(op, e1, e2):
				expr(e1);
				add(" " + Printer.getBinaryOp(op) + " ");
				expr(e2);
			case EUnop(op, pre, e):
				if( pre ) {
					add(Printer.getUnaryOp(op));
					expr(e);
				} else {
					expr(e);
					add(Printer.getUnaryOp(op));
				}
			case ECall(e, args):
				if( e == null )
					expr(e);
				else switch( Tools.expr(e) ) {
					case EField(_), EIdent(_), EConst(_):
						expr(e);
					default:
						add("(");
						expr(e);
						add(")");
				}
				add("(");
				var first = true;
				for( a in args ) {
					if( first ) first = false else add(", ");
					expr(a);
				}
				add(")");
			case EIf(cond,e1,e2):
				add("if ("); expr(cond); add(") ");
				expr(e1);
				if( e2 != null ) {
					add(" else ");
					expr(e2);
				}
			case EWhile(cond,e):
				add("while ");
				expr(cond);
				add(" ");
				expr(e);
			case EDoWhile(cond,e):
				add("do");
				expr(e);
				add(" while ");
				expr(cond);
				add(" ");
			case EFor(v, it, e, ithv):
				if(ithv != null)
					add("for( " + ithv + " => " + v + " in ");
				else
					add("for( " + v + " in ");
				expr(it);
				add(" ) ");
				expr(e);
			case EBreak:
				add("break");
			case EContinue:
				add("continue");
			case EFunction(params, e, name, ret, a):
				var aStr = Std.string(a);
				if (aStr.length > 0)
				{
					add(aStr);
					add(" ");
				}
				add("function");
				if( name != null )
					add(" " + name);
				add("(");
				var first = true;
				for( a in params ) {
					if( first ) first = false else add(", ");
					if( a.opt ) add("?");
					add(a.name);
					addType(a.t);
				}
				add(")");
				addType(ret);
				add(" ");
				expr(e);
			case EReturn(e):
				add("return");
				if( e != null ) {
					add(" ");
					expr(e);
				}
			case EArray(e,index):
				expr(e);
				add("[");
				tabs += "\t";
				expr(index);
				tabs = tabs.substring(1);
				add("]");
			case EArrayDecl(el, _):
				add("[");
				tabs += "\t";
				var first = true;
				for( e in el ) {
					if( first ) first = false else add(", ");
					expr(e);
				}
				tabs = tabs.substring(1);
				add("]");
			case ENew(cl, args):
				add("new " + cl + "(");
				var first = true;
				for( e in args ) {
					if( first ) first = false else add(", ");
					expr(e);
				}
				add(")");
			case EThrow(e):
				add("throw ");
				expr(e);
			case ETry(e, v, t, ecatch):
				add("try ");
				expr(e);
				add(" catch( " + v);
				addType(t);
				add(") ");
				expr(ecatch);
			case EObject(fl):
				if( fl.length == 0 ) {
					add("{}");
				} else {
					tabs += "\t";
					add("{\n");
					for( f in fl ) {
						add(tabs);
						add(f.name);
						add(" : ");
						expr(f.e);
						add(",\n");
					}
					tabs = tabs.substring(1);
					add(tabs);
					add("}");
				}
			case ETernary(c,e1,e2):
				expr(c);
				add(" ? ");
				expr(e1);
				add(" : ");
				expr(e2);
			case ESwitch(e, cases, def):
				add("switch ");
				expr(e);
				add(" {\n");
				tabs += "\t";
				for( c in cases ) {
					add(tabs);
					add("case ");
					var first = true;
					for( v in c.values ) {
						if( first ) first = false else add(", ");
						expr(v);
					}
					add(": ");
					// tabs += "\t";
					expr(c.expr);
					add(";\n");
					// tabs = tabs.substring(1);
				}
				if( def != null ) {
					add(tabs);
					add("default: ");
					// tabs += "\t";
					expr(def);
					// tabs = tabs.substring(1);
					add(";\n");
				}
				tabs = tabs.substring(1);
				add(tabs);
				add("}");
			case EMeta(name, args, e):
				add("@");
				add(name);
				if( args != null && args.length > 0 ) {
					add("(");
					var first = true;
					for( a in args ) {
						if( first ) first = false else add(", ");
						expr(e);
					}
					add(")");
				}
				add(" ");
				expr(e);
			case ECheckType(e, t):
				add("(");
				expr(e);
				add(" : ");
				addType(t);
				add(")");
		}
	}

	public static inline function toString( e : Expr ) {
		return new Printer().exprToString(e);
	}

	public static function getBinaryOp(op:Binop) {
		return switch(op) {
			case OpAdd: "+";
			case OpSub: "-";
			case OpMult: "*";
			case OpDiv: "/";
			case OpMod: "%";
			case OpAnd: "&";
			case OpOr: "|";
			case OpXor: "^";
			case OpShl: "<<";
			case OpShr: ">>";
			case OpUShr: ">>>";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpIs: "is";
			case OpNullCoal: "??";
			case OpAssign: "=";
			case OpArrow: "=>";
			case OpInterval: "...";
			case OpAssignOp(op): getBinaryOp(op) + "=";
		}
	}

	public static function getUnaryOp(op:Unop) {
		return switch(op) {
			case OpIncrement: "++";
			case OpDecrement: "--";
			case OpNot: "!";
			case OpNeg: "-";
			case OpNegBits: "~";
			case OpSpread: "...";
		}
	}

	public static function errorToStringMessage( e : Expr.Error ) {
		return switch( Tools.cleanError(e) ) {
			case EInvalidChar(c): "Invalid character: '" + (StringTools.isEof(c) ? "EOF (End Of File)" : String.fromCharCode(c)) + "' (" + c + ")";
			case EUnexpected(s): "Unexpected token: \"" + s + "\"";
			case EUnterminatedString: "Unterminated string";
			case EUnterminatedComment: "Unterminated comment";
			case EUnterminatedRegex: "Unterminated regular expression";
			case EInvalidPreprocessor(str): "Invalid preprocessor (" + str + ")";
			case EUnknownVariable(v): "Unknown variable: " + v;
			case EInvalidIterator(v): "Invalid iterator: " + v;
			case EInvalidType(t): "Invalid type: " + t;
			case EInvalidOp(op): "Invalid operator: " + op;
			case EInvalidAccess(f, on) if (on != null): "Invalid access to field " + f + " on " + on;
			case EInvalidAccess(f): "Invalid access to field " + f;
			case ECustom(msg): msg;
			case EPreset(msg): msg.toString();
			case EInvalidClass(cla): "Invalid class: " + cla + " was not found.";
			case EAlreadyExistingClass(cla): "Custom Class named " + cla + " already exists.";
			case EInvalidEscape(s): "Invalid escape sequence: " + s;
		}
	}

	public #if !hscriptPos inline #end static function errorToString( e : Expr.Error ) {
		#if hscriptPos
		return e.origin + ":" + e.line + ": " + errorToStringMessage(e);
		#else
		return errorToStringMessage(e);
		#end
	}

	public static inline function convertTypeToString( t : CType ) {
		return new Printer().typeToString(t);
	}

	public static inline function convertExprToString( e : Expr ) {
		return toString(e);
	}

}