/*
 * Copyright (c) 2008, Nicolas Cannasse
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
package hscript;
import hscript.Expr;

enum Token {
	TEof;
	TConst( c : Const );
	TId( s : String );
	TOp( s : String );
	TPOpen;
	TPClose;
	TBrOpen;
	TBrClose;
	TDot;
	TComma;
	TSemicolon;
	TBkOpen;
	TBkClose;
	TQuestion;
	TDoubleDot;
}

class Parser {

	// config / variables
	public var line : Int;
	public var opChars : String;
	public var identChars : String;
	public var opPriority : Array<String>;
	public var unopsPrefix : Array<String>;
	public var unopsSuffix : Array<String>;

	/**
		activate JSON compatiblity
	**/
	public var allowJSON : Bool;
	
	/**
		allow types declarations
	**/
	public var allowTypes : Bool;

	// implementation
	var input : haxe.io.Input;
	var char : Null<Int>;
	var ops : Array<Bool>;
	var idents : Array<Bool>;
	var tokens : haxe.FastList<Token>;

	public function new() {
		line = 1;
		opChars = "+*/-=!><&|^%~";
		identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
		opPriority = [
			"...",
			"=",
			"||","&&",
			"==","!=",">","<",">=","<=",
			"|","&","^",
			"<<",">>",">>>",
			"+","-",
			"*","/",
			"%"
		];
		unopsPrefix = ["!","++","--","-","~"];
		unopsSuffix = ["++","--"];
	}

	public function parseString( s : String ) {
		line = 1;
		return parse( new haxe.io.StringInput(s) );
	}

	public function parse( s : haxe.io.Input ) {
		char = null;
		input = s;
		ops = new Array();
		idents = new Array();
		tokens = new haxe.FastList<Token>();
		for( i in 0...opChars.length )
			ops[opChars.charCodeAt(i)] = true;
		for( i in 0...identChars.length )
			idents[identChars.charCodeAt(i)] = true;
		var a = new Array();
		while( true ) {
			var tk = token();
			if( tk == TEof ) break;
			push(tk);
			a.push(parseFullExpr());
		}
		return if( a.length == 1 ) a[0] else EBlock(a);
	}

	function unexpected( tk ) : Dynamic {
		throw Error.EUnexpected(tokenString(tk));
		return null;
	}
	
	inline function push(tk) {
		tokens.add(tk);
	}
	
	inline function ensure(tk) {
		var t = token();
		if( t != tk ) unexpected(t);
	}

	function isBlock(e) {
		return switch( e ) {
		case EBlock(_), EObject(_): true;
		case EFunction(_,e,_,_): isBlock(e);
		case EVar(_,_,e): e != null && isBlock(e);
		case EIf(_,e1,e2): if( e2 != null ) isBlock(e2) else isBlock(e1);
		case EBinop(_,_,e): isBlock(e);
		case EUnop(_,prefix,e): !prefix && isBlock(e);
		case EWhile(_,e): isBlock(e);
		case EFor(_,_,e): isBlock(e);
		case EReturn(e): e != null && isBlock(e);
		default: false;
		}
	}

	function parseFullExpr() {
		var e = parseExpr();
		var tk = token();
		if( tk != TSemicolon && tk != TEof ) {
			if( isBlock(e) )
				push(tk);
			else
				unexpected(tk);
		}
		return e;
	}

	function parseObject() {
		// parse object
		var fl = new Array();
		while( true ) {
			var tk = token();
			var id = null;
			switch( tk ) {
			case TId(i): id = i;
			case TConst(c):
				if( !allowJSON )
					unexpected(tk);
				switch( c ) {
				case CString(s): id = s;
				default: unexpected(tk);
				}
			case TBrClose:
				break;
			default:
				unexpected(tk);
			}
			ensure(TDoubleDot);
			fl.push({ name : id, e : parseExpr() });
			tk = token();
			switch( tk ) {
			case TBrClose:
				break;
			case TComma:
			default:
				unexpected(tk);
			}
		}
		return parseExprNext(EObject(fl));
	}

	function parseExpr() {
		var tk = token();
		switch( tk ) {
		case TId(id):
			var e = parseStructure(id);
			if( e == null )
				e = EIdent(id);
			return parseExprNext(e);
		case TConst(c):
			return parseExprNext(EConst(c));
		case TPOpen:
			var e = parseExpr();
			ensure(TPClose);
			return parseExprNext(EParent(e));
		case TBrOpen:
			tk = token();
			switch( tk ) {
			case TBrClose:
				return parseExprNext(EObject([]));
			case TId(id):
				var tk2 = token();
				push(tk2);
				push(tk);
				switch( tk2 ) {
				case TDoubleDot:
					return parseExprNext(parseObject());
				default:
				}
			case TConst(c):
				if( allowJSON ) {
					switch( c ) {
					case CString(_):
						var tk2 = token();
						push(tk2);
						push(tk);
						switch( tk2 ) {
						case TDoubleDot:
							return parseExprNext(parseObject());
						default:
						}
					default:
						push(tk);
					}
				} else
					push(tk);
			default:
				push(tk);
			}
			var a = new Array();
			while( true ) {
				a.push(parseFullExpr());
				tk = token();
				if( tk == TBrClose )
					break;
				push(tk);
			}
			return EBlock(a);
		case TOp(op):
			var found;
			for( x in unopsPrefix )
				if( x == op )
					return makeUnop(op,parseExpr());
			return unexpected(tk);
		case TBkOpen:
			var a = new Array();
			tk = token();
			while( tk != TBkClose ) {
				push(tk);
				a.push(parseExpr());
				tk = token();
				if( tk == TComma )
					tk = token();
			}
			return parseExprNext(EArrayDecl(a));
		default:
			return unexpected(tk);
		}
	}

	function priority(op) {
		for( i in 0...opPriority.length )
			if( opPriority[i] == op )
				return i;
		return -1;
	}

	function makeUnop( op, e ) {
		return switch( e ) {
		case EBinop(bop,e1,e2): EBinop(bop,makeUnop(op,e1),e2);
		default: EUnop(op,true,e);
		}
	}

	function makeBinop( op, e1, e ) {
		return switch( e ) {
		case EBinop(op2,e2,e3):
			if( priority(op) > priority(op2) )
				EBinop(op2,makeBinop(op,e1,e2),e3);
			else
				EBinop(op,e1,e);
		default: EBinop(op,e1,e);
		}
	}

	function parseStructure(id) {
		return switch( id ) {
		case "if":
			var cond = parseExpr();
			var e1 = parseExpr();
			var e2 = null;
			var semic = false;
			var tk = token();
			if( tk == TSemicolon ) {
				semic = true;
				tk = token();
			}
			if( Type.enumEq(tk,TId("else")) )
				e2 = parseExpr();
			else {
				push(tk);
				if( semic ) push(TSemicolon);
			}
			EIf(cond,e1,e2);
		case "var":
			var tk = token();
			var ident = null;
			switch(tk) {
			case TId(id): ident = id;
			default: unexpected(tk);
			}
			tk = token();
			var t = null;
			if( tk == TDoubleDot && allowTypes ) {
				t = parseType();
				tk = token();
			}
			var e = null;
			if( Type.enumEq(tk,TOp("=")) )
				e = parseExpr();
			else
				push(tk);
			EVar(ident,t,e);
		case "while":
			var econd = parseExpr();
			var e = parseExpr();
			EWhile(econd,e);
		case "for":
			ensure(TPOpen);
			var tk = token();
			var vname = null;
			switch( tk ) {
			case TId(id): vname = id;
			default: unexpected(tk);
			}
			tk = token();
			if( !Type.enumEq(tk,TId("in")) ) unexpected(tk);
			var eiter = parseExpr();
			ensure(TPClose);
			EFor(vname,eiter,parseExpr());
		case "break": EBreak;
		case "continue": EContinue;
		case "else": unexpected(TId(id));
		case "function":
			var tk = token();
			var name = null;
			switch( tk ) {
			case TId(id): name = id;
			default: push(tk);
			}
			ensure(TPOpen);
			var args = new Array();
			tk = token();
			if( tk != TPClose ) {
				while( true ) {
					var name = null;
					switch( tk ) {
					case TId(id): name = id;
					default: unexpected(tk);
					}
					tk = token();
					var t = null;
					if( tk == TDoubleDot && allowTypes ) {
						t = parseType();
						tk = token();
					}
					args.push({ name : name, t : t });
					switch( tk ) {
					case TComma:
					case TPClose: break;
					default: unexpected(tk);
					}
					tk = token();
				}
			}
			var ret = null;
			if( allowTypes ) {
				tk = token();
				if( tk != TDoubleDot )
					push(tk);
				else
					ret = parseType();
			}
			EFunction(args, parseExpr(), name, ret);
		case "return":
			var tk = token();
			push(tk);
			EReturn(if( tk == TSemicolon ) null else parseExpr());
		case "new":
			var a = new Array();
			var tk = token();
			switch( tk ) {
			case TId(id): a.push(id);
			default: unexpected(tk);
			}
			while( true ) {
				tk = token();
				switch( tk ) {
				case TDot:
					tk = token();
					switch(tk) {
					case TId(id): a.push(id);
					default: unexpected(tk);
					}
				case TPOpen:
					break;
				default:
					unexpected(tk);
				}
			}
			ENew(a.join("."),parseExprList(TPClose));
		case "throw":
			EThrow( parseExpr() );
		case "try":
			var e = parseExpr();
			var tk = token();
			if( !Type.enumEq(tk, TId("catch")) ) unexpected(tk);
			ensure(TPOpen);
			tk = token();
			var vname = switch( tk ) {
			case TId(id): id;
			default: unexpected(tk);
			}
			ensure(TDoubleDot);
			var t = null;
			if( allowTypes )
				t = parseType();
			else {
				tk = token();
				if( !Type.enumEq(tk, TId("Dynamic")) ) unexpected(tk);
			}
			ensure(TPClose);
			ETry(e,vname,t,parseExpr());
		default:
			null;
		}
	}

	function parseExprNext( e1 : Expr ) {
		var tk = token();
		switch( tk ) {
		case TOp(op):
			for( x in unopsSuffix )
				if( x == op ) {
					if( isBlock(e1) || switch(e1) { case EParent(_): true; default: false; } ) {
						push(tk);
						return e1;
					}
					return parseExprNext(EUnop(op,false,e1));
				}
			return makeBinop(op,e1,parseExpr());
		case TDot:
			tk = token();
			var field = null;
			switch(tk) {
			case TId(id): field = id;
			default: unexpected(tk);
			}
			return parseExprNext(EField(e1,field));
		case TPOpen:
			return parseExprNext(ECall(e1,parseExprList(TPClose)));
		case TBkOpen:
			var e2 = parseExpr();
			ensure(TBkClose);
			return parseExprNext(EArray(e1,e2));
		case TQuestion:
			var e2 = parseExpr();
			ensure(TDoubleDot);
			var e3 = parseExpr();
			return EIf(e1,e2,e3);
		default:
			push(tk);
			return e1;
		}
	}

	function parseType() : CType {
		var t = token();
		switch( t ) {
		case TId(v):
			var path = [v];
			while( true ) {
				t = token();
				if( t != TDot )
					break;
				t = token();
				switch( t ) {
				case TId(v):
					path.push(v);
				default:
					unexpected(t);
				}
			}
			var params = null;
			switch( t ) {
			case TOp(op):
				if( op == "<" ) {
					params = [];
					while( true ) {
						params.push(parseType());
						t = token();
						switch( t ) {
						case TComma: continue;
						case TOp(op): if( op ==	">" ) break;
						default:
						}
						unexpected(t);
					}
				}
			default:
				push(t);
			}
			return parseTypeNext(CTPath(path, params));
		case TPOpen:
			var t = parseType();
			ensure(TPClose);
			return parseTypeNext(CTParent(t));
		case TBrOpen:
			var fields = [];
			while( true ) {
				t = token();
				switch( t ) {
				case TBrClose: break;
				case TId(name):
					ensure(TDoubleDot);
					fields.push( { name : name, t : parseType() } );
					t = token();
					switch( t ) {
					case TComma:
					case TBrClose: break;
					default: unexpected(t);
					}
				default:
					unexpected(t);
				}
			}
			return parseTypeNext(CTAnon(fields));
		default:
			return unexpected(t);
		}
	}
	
	function parseTypeNext( t : CType ) {
		var tk = token();
		switch( tk ) {
		case TOp(op):
			if( op != "->" ) {
				push(tk);
				return t;
			}
		default:
			push(tk);
			return t;
		}
		var t2 = parseType();
		switch( t2 ) {
		case CTFun(args, ret):
			args.unshift(t);
			return t2;
		default:
			return CTFun([t], t2);
		}
	}
	
	function parseExprList( etk ) {
		var args = new Array();
		var tk = token();
		if( tk == etk )
			return args;
		tokens.add(tk);
		while( true ) {
			args.push(parseExpr());
			tk = token();
			switch( tk ) {
			case TComma:
			default:
				if( tk == etk ) break;
				unexpected(tk);
			}
		}
		return args;
	}

	function readChar() {
		return try input.readByte() catch( e : Dynamic ) 0;
	}

	function readString( until ) {
		var c;
		var b = new haxe.io.BytesOutput();
		var esc = false;
		var old = line;
		var s = input;
		while( true ) {
			try {
				c = s.readByte();
			} catch( e : Dynamic ) {
				line = old;
				throw Error.EUnterminatedString;
			}
			if( esc ) {
				esc = false;
				switch( c ) {
				case 'n'.code: b.writeByte(10);
				case 'r'.code: b.writeByte(13);
				case 't'.code: b.writeByte(9);
				case "'".code, '"'.code, '\\'.code: b.writeByte(c);
				case '/'.code: if( allowJSON ) b.writeByte(c) else throw Error.EInvalidChar(c);
				case "u".code:
					if( !allowJSON ) throw Error.EInvalidChar(c);
					var code;
					try {
						code = s.readString(4);
					} catch( e : Dynamic ) {
						line = old;
						throw Error.EUnterminatedString;
					}
					var k = 0;
					for( i in 0...4 ) {
						k <<= 4;
						var char = code.charCodeAt(i);
						switch( char ) {
						case 48,49,50,51,52,53,54,55,56,57: // 0-9
							k += char - 48;
						case 65,66,67,68,69,70: // A-F
							k += char - 55;
						case 97,98,99,100,101,102: // a-f
							k += char - 87;
						default:
							throw Error.EInvalidChar(char);
						}
					}
					// encode k in UTF8
					if( k <= 0x7F )
						b.writeByte(k);
					else if( k <= 0x7FF ) {
						b.writeByte( 0xC0 | (k >> 6));
						b.writeByte( 0x80 | (k & 63));
					} else {
						b.writeByte( 0xE0 | (k >> 12) );
						b.writeByte( 0x80 | ((k >> 6) & 63) );
						b.writeByte( 0x80 | (k & 63) );
					}
				default: throw Error.EInvalidChar(c);
				}
			} else if( c == 92 )
				esc = true;
			else if( c == until )
				break;
			else {
				if( c == 10 ) line++;
				b.writeByte(c);
			}
		}
		return b.getBytes().toString();
	}

	function token() {
		if( !tokens.isEmpty() )
			return tokens.pop();
		var char;
		if( this.char == null )
			char = readChar();
		else {
			char = this.char;
			this.char = null;
		}
		while( true ) {
			switch( char ) {
			case 0: return TEof;
			case 32,9,13: // space, tab, CR
			case 10: line++; // LF
			case 48,49,50,51,52,53,54,55,56,57: // 0...9
				var n = (char - 48) * 1.0;
				var exp = 0;
				while( true ) {
					char = readChar();
					exp *= 10;
					switch( char ) {
					case 48,49,50,51,52,53,54,55,56,57:
						n = n * 10 + (char - 48);
					case 46:
						if( exp > 0 ) {
							// in case of '...'
							if( exp == 10 && readChar() == 46 ) {
								tokens.add(TOp("..."));
								var i = Std.int(n);
								return TConst( (i == n) ? CInt(i) : CFloat(n) );
							}
							throw Error.EInvalidChar(char);
						}
						exp = 1;
					case 120: // x
						if( n > 0 || exp > 0 )
							throw Error.EInvalidChar(char);
						// read hexa
						var n = haxe.Int32.ofInt(0);
						while( true ) {
							char = readChar();
							switch( char ) {
							case 48,49,50,51,52,53,54,55,56,57: // 0-9
								n = haxe.Int32.add(haxe.Int32.shl(n,4), cast (char - 48));
							case 65,66,67,68,69,70: // A-F
								n = haxe.Int32.add(haxe.Int32.shl(n,4), cast (char - 55));
							case 97,98,99,100,101,102: // a-f
								n = haxe.Int32.add(haxe.Int32.shl(n,4), cast (char - 87));
							default:
								this.char = char;
								// we allow to parse hexadecimal Int32 in Neko, but when the value will be
								// evaluated by Interpreter, a failure will occur if no Int32 operation is
								// performed
								var v = try CInt(haxe.Int32.toInt(n)) catch( e : Dynamic ) CInt32(n);
								return TConst(v);
							}
						}
					default:
						this.char = char;
						var i = Std.int(n);
						return TConst( (exp > 0) ? CFloat(n * 10 / exp) : ((i == n) ? CInt(i) : CFloat(n)) );
					}
				}
			case 59: return TSemicolon;
			case 40: return TPOpen;
			case 41: return TPClose;
			case 44: return TComma;
			case 46:
				char = readChar();
				switch( char ) {
				case 48,49,50,51,52,53,54,55,56,57:
					var n = char - 48;
					var exp = 1;
					while( true ) {
						char = readChar();
						exp *= 10;
						switch( char ) {
						case 48,49,50,51,52,53,54,55,56,57:
							n = n * 10 + (char - 48);
						default:
							this.char = char;
							return TConst( CFloat(n/exp) );
						}
					}
				case 46:
					char = readChar();
					if( char != 46 )
						throw Error.EInvalidChar(char);
					return TOp("...");
				default:
					this.char = char;
					return TDot;
				}
			case 123: return TBrOpen;
			case 125: return TBrClose;
			case 91: return TBkOpen;
			case 93: return TBkClose;
			case 39: return TConst( CString(readString(39)) );
			case 34: return TConst( CString(readString(34)) );
			case 63: return TQuestion;
			case 58: return TDoubleDot;
			default:
				if( ops[char] ) {
					var op = String.fromCharCode(char);
					while( true ) {
						char = readChar();
						if( !ops[char] ) {
							if( op.charCodeAt(0) == 47 )
								return tokenComment(op,char);
							this.char = char;
							return TOp(op);
						}
						op += String.fromCharCode(char);
					}
				}
				if( idents[char] ) {
					var id = String.fromCharCode(char);
					while( true ) {
						char = readChar();
						if( !idents[char] ) {
							this.char = char;
							return TId(id);
						}
						id += String.fromCharCode(char);
					}
				}
				throw Error.EInvalidChar(char);
			}
			char = readChar();
		}
		return null;
	}

	function tokenComment( op : String, char : Int ) {
		var c = op.charCodeAt(1);
		var s = input;
		if( c == 47 ) { // comment
			try {
				while( char != 10 && char != 13 )
					char = s.readByte();
				this.char = char;
			} catch( e : Dynamic ) {
			}
			return token();
		}
		if( c == 42 ) { /* comment */
			var old = line;
			try {
				while( true ) {
					while( char != 42 ) {
						if( char == 10 ) line++;
						char = s.readByte();
					}
					char = s.readByte();
					if( char == 47 )
						break;
				}
			} catch( e : Dynamic ) {
				line = old;
				throw Error.EUnterminatedComment;
			}
			return token();
		}
		this.char = char;
		return TOp(op);
	}

	function constString( c ) {
		return switch(c) {
		case CInt(v): Std.string(v);
		case CInt32(v): Std.string(v);
		case CFloat(f): Std.string(f);
		case CString(s): s; // TODO : escape + quote
		}
	}

	function tokenString( t ) {
		return switch( t ) {
		case TEof: "<eof>";
		case TConst(c): constString(c);
		case TId(s): s;
		case TOp(s): s;
		case TPOpen: "(";
		case TPClose: ")";
		case TBrOpen: "{";
		case TBrClose: "}";
		case TDot: ".";
		case TComma: ",";
		case TSemicolon: ";";
		case TBkOpen: "[";
		case TBkClose: "]";
		case TQuestion: "?";
		case TDoubleDot: ":";
		}
	}

}
