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

#if hscriptPos
//typedef StoredToken = { min : Int, max : Int, t : Token }
@:structInit
class StoredToken {
	public var min : Int;
	public var max : Int;
	public var t : Token;
}
#else
typedef StoredToken = Token;
#end

typedef TokenList = List<StoredToken>;

enum Token {
	TEof;
	TConst( c : Const );
	TInterpString( tkl: Array<TokenList> ); // Stores the tokens that make up the interpolation string
	TRegex( r: String, opt: String );
	TId( s : String );
	TOp( s : String );
	TPOpen;
	TPClose;
	TBrOpen;
	TBrClose;
	TDot;
	TQuestionDot;
	TComma;
	TSemicolon;
	TBkOpen;
	TBkClose;
	TQuestion;
	TDoubleDot;
	TMeta( s : String );
	TPrepro( s : String );
}

class Parser {

	// config / variables
	public var line : Int;
	public var opChars : String;
	public var identChars : String;
	public var startIdentChars : String;
	public var opPriority : Map<String,Int>;
	public var opRightAssoc : Map<String,Bool>;

	/**
		allows to check for #if / #else in code
	**/
	public var preprocesorValues : Map<String,Dynamic> = new Map();

	/**
		activate JSON compatiblity
	**/
	public var allowJSON : Bool;

	/**
		allow types declarations
	**/
	public var allowTypes : Bool;

	/**
		allow regular expressions
	**/
	public var allowEreg : Bool;

	/**
		allow haxe metadata declarations
	**/
	public var allowMetadata : Bool;

	public var convertPreProcValsToStr : Bool;

	/**
		resume from parsing errors (when parsing incomplete code, during completion for example)
	**/
	public var resumeErrors : Bool;

	public var allowStringInterpolation:Bool = true;

	// implementation
	var input : String;
	var readPos : Int;

	var char : Int;
	var ops : Array<Bool>;
	var idents : Array<Bool>;
	var startIdents : Array<Bool>;
	var uid : Int = 0;

	var disableOrOp : Bool = false;

	#if hscriptPos
	var origin : String;
	var tokenMin : Int;
	var tokenMax : Int;
	var oldTokenMin : Int;
	var oldTokenMax : Int;
	#else
	static inline var p1 = 0;
	static inline var tokenMin = 0;
	static inline var tokenMax = 0;
	#end

	var tokens : TokenList;

	public function new() {
		line = 1;
		convertPreProcValsToStr = true;
		opChars = "+*/-=!><&|^%~";
		identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
		startIdentChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_";
		var priorities:Array<Array<String>> = [
			["%"],
			["*", "/"],
			["+", "-"],
			["<<", ">>", ">>>"],
			["|", "&", "^"],
			["==", "!=", ">", "<", ">=", "<="],
			["..."],
			["&&"],
			["||"],
			["=","+=","-=","*=","/=","%=","<<=",">>=",">>>=","|=","&=","^=","=>","??" + "="],
			["->", "??"],
			["is"]
		];
		opPriority = new Map();
		opRightAssoc = new Map();
		for( i => arrPri in priorities )
			for( x in arrPri ) {
				opPriority.set(x, i);
				if( i == 9 ) opRightAssoc.set(x, true);
			}
		for( x in ["!", "++", "--", "~"] ) // unary "-" handled in parser directly!
			opPriority.set(x, x == "++" || x == "--" ? -1 : -2);
	}

	public inline function error( err, pmin, pmax ) {
		if( !resumeErrors )
		#if hscriptPos
		throw new Error(err, pmin, pmax, origin, line);
		#else
		throw err;
		#end
	}

	public function invalidChar(c) {
		error(EInvalidChar(c), readPos-1, readPos-1);
	}

	function initParser( origin ) {
		// line=1 - don't reset line : it might be set manualy
		preprocStack = [];
		#if hscriptPos
		this.origin = origin;
		readPos = 0;
		tokenMin = oldTokenMin = 0;
		tokenMax = oldTokenMax = 0;
		#end
		tokens = new TokenList();
		char = -1;
		ops = new Array();
		idents = new Array();
		startIdents = new Array();
		uid = 0;
		for( i in 0...opChars.length )
			ops[opChars.charCodeAt(i)] = true;
		for( i in 0...identChars.length )
			idents[identChars.charCodeAt(i)] = true;
		for( i in 0...startIdentChars.length )
			startIdents[startIdentChars.charCodeAt(i)] = true;
	}

	public function parseString( s : String, ?origin : String = "hscript" ) : Expr {
		initParser(origin);
		if(s == "") s = "0;"; // fixing crash with empty file
		input = s;
		readPos = 0;
		var a:Array<Expr> = new Array();
		while( true ) {
			var tk:Token = token();
			if( tk == TEof ) break;
			push(tk);
			parseFullExpr(a);
		}
		return if( a.length == 1 ) a[0] else mk(EBlock(a),0);
	}

	function unexpected( tk:Token ) : Dynamic {
		error(EUnexpected(tokenString(tk)),tokenMin,tokenMax);
		return null;
	}


	inline function realToken(tk:Token, ?min:Int, ?max:Int):StoredToken {
		#if hscriptPos
		return {
			t : tk,
			min : min != null ? min : tokenMin,
			max : max != null ? max : tokenMax
		};
		#else
		return tk;
		#end
	}

	inline function push( tk:Token ):Void {
		#if hscriptPos
		tokens.push( realToken(tk) );
		tokenMin = oldTokenMin;
		tokenMax = oldTokenMax;
		#else
		tokens.add(tk);
		#end
	}

	inline function ensure( tk:Token ):Void {
		var t = token();
		if( t != tk ) unexpected(t);
	}

	inline function ensureToken( tk:Token ):Void {
		var t:Token = token();
		if( !Type.enumEq(t,tk) ) unexpected(t);
	}

	function maybe( tk:Token ):Bool {
		var t:Token = token();
		if( Type.enumEq(t, tk) )
			return true;
		push(t);
		return false;
	}

	function getIdent():String {
		var tk:Token = token();
		switch( tk ) {
			case TId(id): return id;
			default:
				unexpected(tk);
				return null;
		}
	}

	inline function expr(e:Expr) {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	inline function pmin(e:Expr):Int {
		#if hscriptPos
		return e == null ? 0 : e.pmin;
		#else
		return 0;
		#end
	}

	inline function pmax(e:Expr):Int {
		#if hscriptPos
		return e == null ? 0 : e.pmax;
		#else
		return 0;
		#end
	}

	inline function mk( e: Null<ExprDef>, ?pmin: Null<Int>, ?pmax: Null<Int> ) : Expr {
		#if hscriptPos
		if( e == null ) return null;
		if( pmin == null ) pmin = tokenMin;
		if( pmax == null ) pmax = tokenMax;
		return { e : e, pmin : pmin, pmax : pmax, origin : origin, line : line };
		#else
		return e;
		#end
	}

	function isBlock( e: Null<Expr> ) {
		if( e == null ) return false;
		return switch( expr(e) ) {
			case EBlock(_), EObject(_), ESwitch(_): true;
			case EFunction(_,e): isBlock(e);
			case EClass(_,e): true;
			case EVar(_, t, e): e != null ? isBlock(e) : t != null ? t.match(CTAnon(_)) : false;
			case EIf(_,e1,e2): if( e2 != null ) isBlock(e2) else isBlock(e1);
			case EBinop(_,_,e): isBlock(e);
			case EUnop(_,prefix,e): !prefix && isBlock(e);
			case EWhile(_,e): isBlock(e);
			case EDoWhile(_,e): isBlock(e);
			case EFor(_,_,e): isBlock(e);
			case EReturn(e): isBlock(e);
			case ETry(_, _, _, e): isBlock(e);
			case EMeta(_, _, e): isBlock(e);
			default: false;
		}
	}

	function parseFullExpr( exprs : Array<Expr> ) {
		var e = parseExpr();
		exprs.push(e);

		var tk = token();
		// this is a hack to support var a,b,c; with a single EVar
		while( tk == TComma && e != null && expr(e).match(EVar(_)) ) {
			e = parseStructure("var"); // next variable
			exprs.push(e);
			tk = token();
		}

		if( tk != TSemicolon && tk != TEof ) {
			if( isBlock(e) )
				push(tk);
			else
				unexpected(tk);
		}
	}


	function parseObject(p1:Int) {
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
				default:
					if (tk != TBrClose)
						unexpected(tk);
					break;
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
		return parseExprNext(mk(EObject(fl),p1));
	}

	function parseExprFromTokens(t:TokenList) {
		var oldPos = readPos;
		#if hscriptPos
		var oldTokenMin = tokenMin;
		var oldTokenMax = tokenMax;
		#end
		var oldTokens = tokens;

		tokens = t;
		// unsure about these
		#if hscriptPos
		tokenMin = 0;
		tokenMax = t.length - 1;
		#end
		readPos = 0;
		//trace(t.map(getTk).map(tokenString));

		var e = parseExpr();

		tokens = oldTokens;
		#if hscriptPos
		tokenMin = oldTokenMin;
		tokenMax = oldTokenMax;
		#end
		readPos = oldPos;
		return e;
	}

	function parseExpr() {
		var oldPos = readPos;
		var tk = token();
		#if hscriptPos
		var p1 = tokenMin;
		#end
		switch( tk ) {
			case TId(id):
				var e = parseStructure(id, oldPos);
				if( e == null )
					e = mk(EIdent(id));
				return parseExprNext(e);
			case TConst(c):
				return parseExprNext(mk(EConst(c)));
			case TInterpString(tg):
				if(tg.length == 0)
					return parseExprNext(mk(EConst(CString(""))));

				var e = null;
				var tg = [for(t in tg) if(t.length > 0) t]; // Copy the array and remove empty objects

				var needsCasting = !getTk(tg[0].first()).match(TConst(CString(_)));
				if(needsCasting) {
					tg.unshift(getTokenList(TConst(CString("")))); // add a dummy string to force casting
				}
				function addToMultiString(er:Expr) {
					if(e == null) {
						e = er;
						return;
					}
					// Make it so that the parenthesis are not optimized
					switch(Tools.expr(er)) {
						case EParent(e):
							er = mk(EParent(e));
							/*
							switch(Tools.expr(e)) {
								case EIdent(_) | EConst(_): // The parenthesis are not needed for constants
									er = mk(EParent(e, false));
								default:
									er = mk(EParent(e, true));
							}
							*/
						default:
					}
					e = mk(EBinop(OpAdd, e, er));
					//e = mk(EParent(e));
				}
				while(tg.length > 0) {
					var t = tg.shift();
					if(t.length == 0)
						continue;
					if(t.length == 1) {
						var tk = t.first();
						switch(getTk(tk)) {
							case TConst(c):
								addToMultiString(mk(EConst(c)));
							default:
								addToMultiString(parseExprFromTokens(t));
						}
					} else {
						addToMultiString(parseExprFromTokens(t));
					}
				}

				return parseExprNext(e);
			case TRegex(r, opt):
				var e = mk(EParent(mk(ENew("EReg", [mk(EConst(CString(r))), mk(EConst(CString(opt)))]), p1)), p1);
				return parseExprNext(e);
			case TPOpen:
				tk = token();
				if( tk == TPClose ) {
					ensureToken(TOp("->"));
					var eret = parseExpr();
					return mk(EFunction([], mk(EReturn(eret),p1)), p1);
				}
				push(tk);
				var oldoo = disableOrOp;
				disableOrOp = false;
				var e = parseExpr();
				disableOrOp = oldoo;
				tk = token();
				switch( tk ) {
					case TPClose:
						return parseExprNext(mk(EParent(e),p1,tokenMax));
					case TDoubleDot:
						var t = parseType();
						tk = token();
						switch( tk ) {
							case TPClose:
								return parseExprNext(mk(ECheckType(e,t),p1,tokenMax));
							case TComma:
								switch( expr(e) ) {
									case EIdent(v): return parseLambda([new Argument(v, t)], pmin(e));
									default:
								}
							default:
						}
					case TComma:
						switch( expr(e) ) {
							case EIdent(v): return parseLambda([new Argument(v)], pmin(e));
							default:
						}
					default:
				}
				return unexpected(tk);
			case TBrOpen:
				tk = token();
				switch( tk ) {
					case TBrClose:
						return parseExprNext(mk(EObject([]),p1));
					case TId(_):
						var tk2 = token();
						push(tk2);
						push(tk);
						switch( tk2 ) {
							case TDoubleDot:
								return parseExprNext(parseObject(p1));
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
											return parseExprNext(parseObject(p1));
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
					parseFullExpr(a);
					tk = token();
					if( tk == TBrClose || (resumeErrors && tk == TEof) )
						break;
					push(tk);
				}
				return mk(EBlock(a),p1);
			case TOp(op):
				if( op == "-" ) {
					var start = tokenMin;
					var oldoo = disableOrOp;
					disableOrOp = false;
					var e = parseExpr();
					disableOrOp = oldoo;
					if( e == null )
						return makeUnop(op,e);
					switch( expr(e) ) {
						case EConst(CInt(i)):
							return mk(EConst(CInt(-i)), start, pmax(e));
						case EConst(CFloat(f)):
							return mk(EConst(CFloat(-f)), start, pmax(e));
						default:
							return makeUnop(op,e);
					}
				}
				if( opPriority.get(op) < 0 )
					return makeUnop(op,parseExpr());
				return unexpected(tk);
			case TBkOpen:
				var a = new Array();
				tk = token();
				while( tk != TBkClose && (!resumeErrors || tk != TEof) ) {
					push(tk);
					var oldoo = disableOrOp;
					disableOrOp = false;
					a.push(parseExpr());
					disableOrOp = oldoo;
					tk = token();
					if( tk == TComma )
						tk = token();
				}
				if( a.length == 1 && a[0] != null ) // What is this for???
					switch( expr(a[0]) ) {
						case EFor(_), EWhile(_), EDoWhile(_):
							var tmp = "__a_" + (uid++);
							var e = mk(EBlock([
								mk(EVar(tmp, null, mk(EArrayDecl([]), p1)), p1),
								mapCompr(tmp, a[0]),
								mk(EIdent(tmp),p1),
							]),p1);
							return parseExprNext(e);
						default:
					}
				return parseExprNext(mk(EArrayDecl(a, nextType), p1));
			case TMeta(id) if( allowMetadata ):
				var args = parseMetaArgs();
				return mk(EMeta(id, args, parseExpr()),p1);
			default:
				return unexpected(tk);
		}
	}

	function parseRegex():Expr
	{
		var char:Int = 0;
		var expresion:String = "";
		var flags:String = "";
		var nextIsFlags = false;

		var old = line;

		#if hscriptPos
		var p1 = tokenMin;
		#end

		while (true)
		{
			if (this.char < 0)
				char = readChar();
			else
			{
				char = this.char;
				this.char = -1;
			}

			if (StringTools.isEof(char))
			{
				line = old;
				error(EUnterminatedString, p1, p1);
				break;
			}

			if (char == '/'.code)
			{
				if (nextIsFlags)
				{
					line = old;
					error(EUnterminatedString, p1, p1);
					break;
				}
				nextIsFlags = true;
			}
			else
			{
				if (char == '\n'.code)
					line++;

				if (!nextIsFlags)
				{
					expresion += String.fromCharCode(char);
					if (char == "\\".code)
					{
						var char = readChar();
						if (StringTools.isEof(char))
						{
							line = old;
							error(EUnterminatedString, p1, p1);
						}
						expresion += String.fromCharCode(char);
					}
				}
				else
				{
					if (char == "i".code || char == "g".code || char == "s".code || char == "u".code || char == "m".code) // all valid ereg flags
					{
						flags += String.fromCharCode(char);
					}
					else
					{
						readPos--;
						break;
					}
				}
			}
		}
		// trace(expresion, flags);
		return mk(ENew("EReg", [mk(EConst(CString(expresion))), mk(EConst(CString(flags)))]));
	}

	function parseLambda( args : Array<Argument>, pmin:Int ) {
		while( true ) {
			var id = getIdent();
			var t = maybe(TDoubleDot) ? parseType() : null;
			args.push(new Argument(id, t));
			var tk = token();
			switch( tk ) {
				case TComma:
				case TPClose:
					break;
				default:
					unexpected(tk);
					break;
			}
		}
		ensureToken(TOp("->"));
		var eret = parseExpr();
		return mk(EFunction(args, mk(EReturn(eret),pmin)), pmin);
	}

	function parseMetaArgs() {
		var tk = token();
		if( tk != TPOpen ) {
			push(tk);
			return null;
		}
		var args = [];
		tk = token();
		if( tk != TPClose ) {
			push(tk);
			while( true ) {
				args.push(parseExpr());
				switch( token() ) {
				case TComma:
				case TPClose:
					break;
				case tk:
					unexpected(tk);
				}
			}
		}
		return args;
	}

	function mapCompr( tmp : String, e : Expr ) {
		if( e == null ) return null;
		var edef = switch( expr(e) ) {
			case EFor(v, it, e2, ithv):
				EFor(v, it, mapCompr(tmp, e2), ithv);
			case EWhile(cond, e2):
				EWhile(cond, mapCompr(tmp, e2));
			case EDoWhile(cond, e2):
				EDoWhile(cond, mapCompr(tmp, e2));
			case EIf(cond, e1, e2) if( e2 == null ):
				EIf(cond, mapCompr(tmp, e1), null);
			case EBlock([e]):
				EBlock([mapCompr(tmp, e)]);
			case EParent(e2):
				EParent(mapCompr(tmp, e2));
			default:
				ECall( mk(EField(mk(EIdent(tmp), pmin(e), pmax(e)), "push"), pmin(e), pmax(e)), [e]);
		}
		return mk(edef, pmin(e), pmax(e));
	}

	function makeUnop( op:String, e:Expr ):Expr {
		var op = Tools.getUnopEnum(op);
		return _makeUnop(op, e);
	}

	function _makeUnop( op:Unop, e:Expr ):Expr {
		if( e == null && resumeErrors )
			return null;
		return switch( Tools.expr(e) ) {
			case EBinop(bop, e1, e2): mk(EBinop(bop, _makeUnop(op, e1), e2), pmin(e1), pmax(e2));
			case ETernary(e1, e2, e3): mk(ETernary(_makeUnop(op, e1), e2, e3), pmin(e1), pmax(e3));
			default: mk(EUnop(op,true,e),pmin(e),pmax(e));
		}
	}

	function makeBinop( op:String, e1:Expr, e:Expr ) {
		// TODO: clean this up
		if(!Tools.isValidBinOp(op))
			error(EInvalidOp(op),pmin(e1),pmax(e1));
		var op = Tools.getOpEnum(op);
		return _makeBinop(op, e1, e);
	}

	function _makeBinop( op:Binop, e1:Expr, e:Expr ) {
		// TODO: clean this up
		if( e == null && resumeErrors )
			return mk(EBinop(op,e1,e),pmin(e1),pmax(e1));
		return switch( Tools.expr(e) ) {
			case EBinop(op2,e2,e3):
				if( opPriority.get(Printer.getBinaryOp(op)) <= opPriority.get(Printer.getBinaryOp(op2)) && !opRightAssoc.exists(Printer.getBinaryOp(op)) )
					mk(EBinop(op2,_makeBinop(op,e1,e2),e3),pmin(e1),pmax(e3));
				else
					mk(EBinop(op, e1, e), pmin(e1), pmax(e));
			case ETernary(e2,e3,e4):
				if( opRightAssoc.exists(Printer.getBinaryOp(op)) )
					mk(EBinop(op,e1,e),pmin(e1),pmax(e));
				else
					mk(ETernary(_makeBinop(op, e1, e2), e3, e4), pmin(e1), pmax(e));
			default:
				mk(EBinop(op,e1,e),pmin(e1),pmax(e));
		}
	}

	var nextIsOverride:Bool = false;
	var nextIsStatic:Bool = false;
	var nextIsPublic:Bool = false;
	var nextIsPrivate:Bool = false;
	var nextIsInline:Bool = false;
	var nextIsFinal:Bool = false;
	var nextType:CType = null;
	function parseStructure(id:String, ?oldPos:Int) {
		#if hscriptPos
		var p1 = tokenMin;
		#end
		return switch( id ) {
			case "if":
				ensure(TPOpen);
				var cond = parseExpr();
				ensure(TPClose);
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
				mk(EIf(cond,e1,e2),p1,(e2 == null) ? tokenMax : pmax(e2));
			case "override":
				nextIsOverride = true;
				var nextToken = token();
				switch(nextToken) {
					case TId(_i = "private" | "public" | "inline" | "function" | "static" | "var" | "final"):
						var str = parseStructure(_i);
						nextIsOverride = false;
						str;
					default:
						unexpected(nextToken);
						nextIsOverride = false;
						null;
				}
			case "static":
				nextIsStatic = true;
				var nextToken = token();
				switch(nextToken) {
					case TId(_i = "private" | "public" | "inline" | "function" | "override" | /* "class" |*/ "var" | "final"):
						var str = parseStructure(_i);
						nextIsStatic = false;
						str;
					default:
						unexpected(nextToken);
						nextIsStatic = false;
						null;
				}
			case "public":
				nextIsPublic = true;
				var nextToken = token();
				switch(nextToken) {
					case TId(_i = "class" | "static" | "inline" | "function" | "override" | "var" | "final"):
						var str = parseStructure(_i);
						nextIsPublic = false;
						str;
					//case TId("private"):
					//	var str = parseStructure("private"); // public private
					//	nextIsPublic = false;
					//	str;
					default:
						unexpected(nextToken);
						nextIsPublic = false;
						null;
				}
			case "private":
				nextIsPrivate = true;
				var nextToken = token();
				switch(nextToken) {
					case TId(_i = "static" | "function" | "inline" | "override" | "var" | "final" | "class"):
						var str = parseStructure(_i);
						nextIsPrivate = false;
						str;
					default:
						unexpected(nextToken);
						nextIsPrivate = false;
						null;
				}
			case "inline":
				nextIsInline = true;
				var nextToken = token();
				switch(nextToken) {
					case TId(_i = "static" | "function" | "override" | "var" | "final" | "class" | "private"):
						var str = parseStructure(_i);
						nextIsInline = false;
						str;
					default:
						unexpected(nextToken);
						nextIsInline = false;
						null;
				}
			case "var" | "final":
				if(id == "final") {
					var nextToken = token();
					switch(nextToken) {
						case TId(_i = "class" | "function"):
							nextIsFinal = true;
							var str = parseStructure(_i); // final class | function
							nextIsFinal = false;
							return str;
						default:
							push(nextToken);
					}
				}
				var ident = getIdent();
				var get = null, set = null;
				if( maybe(TPOpen) ) {
					get = getIdent();
					ensure(TComma);
					set = getIdent();
					ensure(TPClose);
				}
				var tk = token();
				var t = null;
				nextType = null;
				if( tk == TDoubleDot && allowTypes ) {
					t = parseType();
					tk = token();

					nextType = t;
				}
				var e = null;
				if( Type.enumEq(tk,TOp("=")) )
					e = parseExpr();
				else
					push(tk);
				nextType = null;
				mk(EVar(ident, t, e, new EFieldAccess(nextIsPublic, nextIsInline, false, nextIsStatic, id == "final")), p1, (e == null) ? tokenMax : pmax(e));
			case "while":
				var econd = parseExpr();
				var e = parseExpr();
				mk(EWhile(econd,e),p1,pmax(e));
			case "do":
				var e = parseExpr();
				var tk = token();
				switch(tk)
				{
					case TId("while"): // Valid
					default: unexpected(tk);
				}
				var econd = parseExpr();
				mk(EDoWhile(econd,e),p1,pmax(econd));
			case "for":
				ensure(TPOpen);
				var ithv:String = null;
				var vname = getIdent();
				var tk = token();
				if( Type.enumEq(tk,TOp("=>")) ) {
					var old = vname;
					vname = getIdent();
					ithv = old;
				} else {
					push(tk);
				}
				ensureToken(TId("in"));
				var eiter = parseExpr();
				ensure(TPClose);
				var e = parseExpr();
				mk(EFor(vname,eiter,e,ithv),p1,pmax(e));
			case "break":	  mk(EBreak);
			case "continue":  mk(EContinue);
			case "else":	  unexpected(TId(id));
			// case "inline":
			// 	if( !maybe(TId("function")) ) unexpected(TId("inline"));
			// 	return parseStructure("function");
			case "function":
				var tk = token();
				var name = null;
				switch( tk ) {
					case TId(id): name = id;
					default: push(tk);
				}
				var inf = parseFunctionDecl();

				var tk = token();
				push(tk);
				mk(EFunction(
						inf.args, inf.body,
						name, inf.ret,
						new EFieldAccess(nextIsPublic, nextIsInline, nextIsOverride, nextIsStatic, nextIsFinal)
					), p1, pmax(inf.body));
			case "import":
				var oldReadPos = readPos;
				var tk = token();
				switch( tk ) {
					case TPOpen:
						var tok = token();
						switch(tok) {
							case TConst(c):
								switch(c) {
									case CString(s):
										token();
										ensure(TSemicolon);
										push(TSemicolon);
										mk(StringTools.endsWith(s, "*") ? EImportStar(s.substr(0, s.length - 1)) : EImport(s), p1);
									default:
										unexpected(tok);
										null;
								}
							default:
								unexpected(tok);
								null;
						}
					case TId(id):
						var path = [id];
						var asname:String = null;
						var t = null;
						var star:Bool = false;
						while( true ) {
							t = token();
							if( t != TDot ) {
								if(t.match(TId("as"))) {
									t = token();
									switch( t ) {
										case TId(id):
											asname = id;
										default:
											unexpected(t);
									}
									break;
								}

								push(t);
								break;
							}
							t = token();
							switch( t ) {
								case TId(id):
									path.push(id);
								case TOp("*"):
									if (star)
										unexpected(t);
									star = true;
								default:
									unexpected(t);
							}
						}
						ensure(TSemicolon);
						push(TSemicolon);
						var p = path.join(".");
						mk(star ? EImportStar(p) : EImport(p, asname), p1);
					default:
						unexpected(tk);
						null;
					}

				case "using":
					var oldReadPos = readPos;
					var tk = token();
					switch( tk ) {
						case TPOpen:
							var tok = token();
							switch(tok) {
								case TConst(c):
									switch(c) {
										case CString(s):
											token();
											ensure(TSemicolon);
											push(TSemicolon);
											mk(EUsing(s), p1);
										default:
											unexpected(tok);
											null;
									}
								default:
									unexpected(tok);
									null;
							}
						case TId(id):
							var path = [id];
							var t = null;
							while( true ) {
								t = token();
								if( t != TDot ) {
									push(t);
									break;
								}
								t = token();
								switch( t ) {
									case TId(id):
										path.push(id);
									default:
										unexpected(t);
								}
							}
							ensure(TSemicolon);
							push(TSemicolon);
							var p = path.join(".");
							mk(EUsing(p), p1);
						default:
							unexpected(tk);
							null;
						}

			case "class":
				// example: class ClassName
				var tk = token();
				var name = null;

				switch (tk) {
					case TId(id): name = id;
					default: push(tk);
				}

				var extend:String = null;
				var interfaces:Array<String> = [];
				// optional - example: extends BaseClass

				while( true ) {
					var t = token();
					switch( t ) {
						case TId(id):
							switch (id)
							{
								case "extends":
									var e = parseType();
									switch(e) {
										case CTPath(path, params):
											if(extend != null) {
												error(ECustom('Cannot extend a class twice.'), 0, 0);
											}
											extend = path.join(".");
										default:
											error(ECustom('${Std.string(e)} is not a valid path.'), 0, 0);
									}
								case "implements":
									var e = parseType();
									switch(e) {
										case CTPath(path, params):
											var strPath = path.join(".");
											if(interfaces.contains(strPath)) {
												error(ECustom('Cannot implement ${strPath} in class twice.'), 0, 0);
											}
											interfaces.push(strPath);
										default:
											error(ECustom('${Std.string(e)} is not a valid path.'), 0, 0);
									}
							}
						default:
							push(t);
							break;
					}
				}

				/*while(true) {
					tk = token();
					trace(tk);
					switch (tk) {
						case TId(id):
							if (id == "extends") {
								tk = token();
								if(extend != null) {
									unexpected(tk);
								} else {
									switch (tk) {
										case TId(id): extend = id;
										default: unexpected(tk);
									}
								}
							} else if (id == "implements") {
								tk = token();
								switch (tk) {
									case TId(id): interfaces.push(id);
									default: unexpected(tk);
								}
							} else {
								//push(tk);
							}

						case TBrOpen:
							push(tk);
							break;

						default:
							//push(tk);
					}
				}*/

				var oldOrigin = this.origin;
				if (name != null)
					this.origin += '.$name';
					// this.origin += '(class:$name)';
				var fields = [];
				ensure(TBrOpen);
				while( true ) {
					parseFullExpr(fields);
					tk = token();
					if( tk == TBrClose || (resumeErrors && tk == TEof) )
						break;
					push(tk);
				}

				this.origin = oldOrigin;

				var tk = token();
				push(tk);
				mk(EClass(name, fields, extend, interfaces, nextIsFinal, nextIsPrivate), p1);

			case "return":
				var tk = token();
				push(tk);
				var e = if( tk == TSemicolon ) null else parseExpr();
				mk(EReturn(e),p1,if( e == null ) tokenMax else pmax(e));
			case "new":
				var a = new Array();
				a.push(getIdent());
				while( true ) {
					var tk = token();
					switch( tk ) {
						case TDot:
							a.push(getIdent());
						case TPOpen:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				var args = parseExprList(TPClose);
				mk(ENew(a.join("."), args), p1);
			case "throw":
				var e = parseExpr();
				mk(EThrow(e),p1,pmax(e));
			case "try":
				var e = parseExpr();
				ensureToken(TId("catch"));
				ensure(TPOpen);
				var vname = getIdent();
				var tk = token();
				var t = null;
				if( allowTypes && tk == TDoubleDot) {
					t = parseType();
				}
				if( tk != TPClose) {
					ensure(TPClose);
				}
				var ec = parseExpr();
				mk(ETry(e, vname, t, ec), p1, pmax(ec));
			case "switch":
				var e = parseExpr();
				var def = null, cases = [];
				ensure(TBrOpen);
				while( true ) {
					var tk = token();
					switch( tk ) {
						case TId("case"):
							var c:SwitchCase = { values : [], expr : null };
							cases.push(c);
							disableOrOp = true;
							while( true ) {
								var e = parseExpr();
								c.values.push(e);
								tk = token();
								switch( tk ) {
									case TComma | TOp("|"):
										// next expr
									case TDoubleDot:
										break;
									default:
										unexpected(tk);
										break;
								}
							}
							disableOrOp = false;
							var exprs = [];
							while( true ) {
								tk = token();
								push(tk);
								switch( tk ) {
									case TId("case" | "default"), TBrClose:
										break;
									case TEof if( resumeErrors ):
										break;
									default:
										parseFullExpr(exprs);
								}
							}
							c.expr = if( exprs.length == 1)
								exprs[0];
							else if( exprs.length == 0 )
								mk(EBlock(exprs), tokenMin, tokenMin);
							else
								mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TId("default"):
							if( def != null ) unexpected(tk);
							ensure(TDoubleDot);
							var exprs = [];
							while( true ) {
								tk = token();
								push(tk);
								switch( tk ) {
									case TId("case" | "default"), TBrClose:
										break;
									case TEof if( resumeErrors ):
										break;
									default:
										parseFullExpr(exprs);
								}
							}
							def = if( exprs.length == 1)
								exprs[0];
							else if( exprs.length == 0 )
								mk(EBlock(exprs), tokenMin, tokenMin);
							else
								mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TBrClose:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				mk(ESwitch(e, cases, def), p1, tokenMax);
			default:
				null;
		}
	}

	function parseExprNext(e1:Expr): Expr {
		var tk = token();
		switch( tk ) {
			case TOp(op):
				if( op == "->" ) {
					// single arg reinterpretation of `f -> e` , `(f) -> e` and `(f:T) -> e`
					switch( Tools.expr(e1) ) {
						case EIdent(i), EParent(Tools.expr(_) => EIdent(i)):
							var eret = parseExpr();
							return mk(EFunction([new Argument(i)], mk(EReturn(eret),pmin(eret))), pmin(e1));
						case ECheckType(Tools.expr(_) => EIdent(i), t):
							var eret = parseExpr();
							return mk(EFunction([new Argument(i, t)], mk(EReturn(eret),pmin(eret))), pmin(e1));
						default:
					}
					unexpected(tk);
				}

				if(disableOrOp && op == "|") {
					push(tk);
					return e1;
				}

				if( opPriority.get(op) == -1 ) {
					if( isBlock(e1) || switch(Tools.expr(e1)) { case EParent(_): true; default: false; } ) { // TODO: clean QQQ
						push(tk);
						return e1;
					}
					return parseExprNext(mk(EUnop(Tools.getUnopEnum(op),false,e1),pmin(e1)));
				}
				return makeBinop(op,e1,parseExpr());

			case TDot | TQuestionDot:
				var field = getIdent();
				return parseExprNext(mk(EField(e1, field, tk == TQuestionDot), pmin(e1)));
			case TPOpen:
				// switch (e1)
				// {
					// case EField(e, "bind"):
					// 	var paramsExpr = parseExprList(TPClose).map(i -> return i.matching(EIdent("_")) ? null : i);
					// 	return mk(EFunction([for (i in paramsExpr) new Argument(i, t)], null, pmin(e1)));
					// default:
						return parseExprNext(mk(ECall(e1,parseExprList(TPClose)),pmin(e1)));
				// }
			case TBkOpen:
				var e2 = parseExpr();
				ensure(TBkClose);
				return parseExprNext(mk(EArray(e1,e2),pmin(e1)));
			case TQuestion:
				var e2 = parseExpr();
				ensure(TDoubleDot);
				var e3 = parseExpr();
				return mk(ETernary(e1,e2,e3),pmin(e1),pmax(e3));
			default:
				push(tk);
				return e1;
		}
	}

	function parseFunctionArgs() {
		var args = new Array();
		var tk = token();
		if( tk != TPClose ) {
			var done = false;
			while( !done ) {
				var name = null, opt = false;
				switch( tk ) {
					case TQuestion:
						opt = true;
						tk = token();
					default:
				}
				switch( tk ) {
					case TId(id): name = id;
					default:
						unexpected(tk);
						break;
				}
				var arg : Argument = new Argument(name);
				args.push(arg);
				if( opt ) arg.opt = true;
				if( allowTypes ) {
					if( maybe(TDoubleDot) )
						arg.t = parseType();
					if( maybe(TOp("="))) {
						arg.value = parseExpr();
						arg.opt = true;
					}
				}
				tk = token();
				switch( tk ) {
					case TComma:
						tk = token();
					case TPClose:
						done = true;
					default:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function parseFunctionDecl() {
		ensure(TPOpen);
		var args = parseFunctionArgs();
		var ret = null;
		if( allowTypes ) {
			var tk = token();
			if( tk != TDoubleDot )
				push(tk);
			else
				ret = parseType();
		}
		final expr = parseExpr();
		switch (expr.e)
		{
			case EBlock(exprBlock): // Fix function without return
				if (!exprBlock[exprBlock.length - 1].e.match(EReturn(_)))
				{
					exprBlock.push(mk(EReturn(null)));
				}
			case _:
		}
		return { args : args, ret : ret, body : expr };
	}

	function parsePath() {
		var path = [getIdent()];
		while( true ) {
			var t = token();
			if( t != TDot ) {
				push(t);
				break;
			}
			path.push(getIdent());
		}
		return path;
	}

	function parseType() : CType {
		var t = token();
		switch( t ) {
			case TId(v):
				push(t);
				var path = parsePath();
				var params = null;
				t = token();
				switch( t ) {
					case TOp(op):
						if( op == "<" ) {
							params = [];
							while( true ) {
								params.push(parseType());
								t = token();
								switch( t ) {
									case TComma: continue;
									case TOp(op):
										if( op == ">" ) break;
										if( op.charCodeAt(0) == ">".code ) {
											#if hscriptPos
											tokens.add({ t : TOp(op.substr(1)), min : tokenMax - op.length - 1, max :tokenMax });
											#else
											tokens.add(TOp(op.substr(1)));
											#end
											break;
										}
									default:
								}
								unexpected(t);
								break;
							}
						} else
							push(t);
					default:
						push(t);
				}
				return parseTypeNext(CTPath(path, params));
			case TPOpen:
				var a = token(),
					b = token();

				push(b);
				push(a);

				function withReturn(args) {
					switch token() { // I think it wouldn't hurt if ensure used enumEq
						case TOp('->'):
						case t: unexpected(t);
					}

					return CTFun(args, parseType());
				}

				switch [a, b] {
					case [TPClose, _] | [TId(_), TDoubleDot]:
						var args = [for (arg in parseFunctionArgs()) {
							switch arg.value {
								case null:
								case v:
									error(ECustom('Default values not allowed in function types'), #if hscriptPos v.pmin, v.pmax #else 0, 0 #end);
							}

							CTNamed(arg.name, if (arg.opt) CTOpt(arg.t) else arg.t);
						}];

						return withReturn(args);
					default:
						var t = parseType();
						return switch token() {
							case TComma:
								var args = [t];

								while (true) {
									args.push(parseType());
									if (!maybe(TComma)) break;
								}
								ensure(TPClose);
								withReturn(args);
							case TPClose:
								parseTypeNext(CTParent(t));
							case t: unexpected(t);
						}
				}
			case TBrOpen:
				var fields = [];
				var meta = null;
				while( true ) {
					t = token();
					switch( t ) {
						case TBrClose: break;
						case TId("var"):
							var name = getIdent();
							ensure(TDoubleDot);
							fields.push( { name : name, t : parseType(), meta : meta } );
							meta = null;
							ensure(TSemicolon);
						case TId("final"):
							var name = getIdent();
							ensure(TDoubleDot);
							if( meta == null ) meta = [];
							meta.push({ name : ":final", params : [] });
							fields.push( { name : name, t : parseType(), meta : meta } );
							meta = null;
							ensure(TSemicolon);
						case TId(name):
							ensure(TDoubleDot);
							fields.push( { name : name, t : parseType(), meta : meta } );
							t = token();
							switch( t ) {
								case TComma:
								case TBrClose: break;
								default: unexpected(t);
							}
						case TMeta(name):
							if( meta == null ) meta = [];
							meta.push({ name : name, params : parseMetaArgs() });
						default:
							unexpected(t);
							break;
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
			case CTFun(args, _):
				args.unshift(t);
				return t2;
			default:
				return CTFun([t], t2);
		}
	}

	function parseExprList( etk:Token ):Array<Expr> {
		var args = new Array();
		var tk = token();
		if( tk == etk )
			return args;
		push(tk);
		while( true ) {
			args.push(parseExpr());
			tk = token();
			switch( tk ) {
				case TComma:
				default:
					if( tk == etk ) break;
					unexpected(tk);
					break;
			}
		}
		return args;
	}

	// ------------------------ module -------------------------------

	public function parseModule( content : String, ?origin : String = "hscript" ) {
		initParser(origin);
		input = content;
		readPos = 0;
		allowTypes = true;
		allowMetadata = true;
		var decls = [];
		while( true ) {
			var tk = token();
			if( tk == TEof ) break;
			push(tk);
			decls.push(parseModuleDecl());
		}
		return decls;
	}

	function parseMetadata() : Metadata {
		var meta = [];
		while( true ) {
			var tk = token();
			switch( tk ) {
				case TMeta(name):
					meta.push({ name : name, params : parseMetaArgs() });
				default:
					push(tk);
					break;
			}
		}
		return meta;
	}

	function parseParams() {
		if( maybe(TOp("<")) )
			error(EInvalidOp("Unsupported class type parameters"), readPos, readPos);
		return {};
	}

	function parseModuleDecl() : ModuleDecl {
		var meta = parseMetadata();
		var ident = getIdent();
		var isPrivate = false, isExtern = false;
		while( true ) {
			switch( ident ) {
				case "private":
					isPrivate = true;
				case "extern":
					isExtern = true;
				default:
					break;
			}
			ident = getIdent();
		}
		switch( ident ) {
			case "package":
				var path = parsePath();
				ensure(TSemicolon);
				return DPackage(path);
			case "import":
				var path = [getIdent()];
				var star = false;
				while( true ) {
					var t = token();
					if( t != TDot ) {
						push(t);
						break;
					}
					t = token();
					switch( t ) {
						case TId(id):
							path.push(id);
						case TOp("*"):
							star = true;
						default:
							unexpected(t);
					}
				}
				ensure(TSemicolon);
				return DImport(path, star);
			case "class":
				var name = getIdent();
				var params = parseParams();
				var extend = null;
				var implement = [];

				while( true ) {
					var t = token();
					switch( t ) {
						case TId("extends"):
							extend = parseType();
						case TId("implements"):
							implement.push(parseType());
						default:
							push(t);
							break;
					}
				}
				var oldOrigin = this.origin;
				if (name != null)
					this.origin += '.$name';
					// this.origin += '(class:$name)';

				var fields = [];
				ensure(TBrOpen);
				while( !maybe(TBrClose) )
					fields.push(parseField());

				this.origin = oldOrigin;
				return DClass({
					name : name,
					meta : meta,
					params : params,
					extend : extend,
					implement : implement,
					fields : fields,
					isPrivate : isPrivate,
					isExtern : isExtern,
				});
			case "typedef":
				var name = getIdent();
				var params = parseParams();
				ensureToken(TOp("="));
				var t = parseType();
				return DTypedef({
					name : name,
					meta : meta,
					params : params,
					isPrivate : isPrivate,
					t : t,
				});
			default:
				unexpected(TId(ident));
		}
		return null;
	}

	function parseField() : FieldDecl {
		var meta = parseMetadata();
		var access = [];
		while( true ) {
			var id = getIdent();
			switch( id ) {
				case "override":
					access.push(AOverride);
				case "public":
					access.push(APublic);
				case "private":
					access.push(APrivate);
				case "inline":
					access.push(AInline);
				case "static":
					access.push(AStatic);
				case "macro":
					access.push(AMacro);
				case "function":
					var name = getIdent();
					var inf = parseFunctionDecl();
					return {
						name : name,
						meta : meta,
						access : access,
						kind : KFunction({
							args : inf.args,
							expr : inf.body,
							ret : inf.ret,
						}),
					};
				case "var":
					var name = getIdent();
					var get = null, set = null;
					if( maybe(TPOpen) ) {
						get = getIdent();
						ensure(TComma);
						set = getIdent();
						ensure(TPClose);
					}
					var type = maybe(TDoubleDot) ? parseType() : null;
					var expr = maybe(TOp("=")) ? parseExpr() : null;

					if( expr != null ) {
						if( isBlock(expr) )
							maybe(TSemicolon);
						else
							ensure(TSemicolon);
					} else if( type != null && type.match(CTAnon(_)) ) {
						maybe(TSemicolon);
					} else
						ensure(TSemicolon);

					return {
						name : name,
						meta : meta,
						access : access,
						kind : KVar({
							get : get,
							set : set,
							type : type,
							expr : expr,
						}),
					};
				default:
					unexpected(TId(id));
					break;
			}
		}
		return null;
	}

	function getTokenList(t:Token) {
		var ls:TokenList = new TokenList();
		ls.add(realToken(t));
		return ls;
	}

	// ------------------------ lexing -------------------------------

	inline function readChar():Int {
		return StringTools.fastCodeAt(input, readPos++);
	}

	inline function peekChar() {
		return StringTools.fastCodeAt(input, readPos);
	}

	static function convertHex(c:Int) {
		return switch( c ) {
			case 48,49,50,51,52,53,54,55,56,57: c - 48; // 0-9
			case 65,66,67,68,69,70: c - 55; // A-F
			case 97,98,99,100,101,102: c - 87; // a-f
			default: -1;
		}
	}

	function readString( until:Int, isSingle:Bool = false ) {
		var c = 0;
		var b = new StringBuf();
		var esc = false;
		var old = line;
		var s = input;
		var p1 = readPos - 1; // No #if check since we need it for the error message
		var ce = ""; // current escape
		var lc = 0; // last char
		function readEscape() {
			var c = lc = readChar();
			if( StringTools.isEof(c) ) {
				line = old;
				error(EUnterminatedString, p1, p1);
				return -1;
			}
			ce += String.fromCharCode(c);
			return c;
		}
		var interpolation = false;
		var interpBlock = false; // true == {} is required | false == no {}
		var interpString:Array<TokenList> = null;
		while( true ) {
			if(interpolation) {
				var arr:TokenList = getTokenList(TPOpen);

				if(interpBlock) {
					var depthStack:Array<Token> = [TBrClose];
					while(true) {
						var tk = token();
						switch(tk) {
							case TEof:
								error(EUnterminatedString, p1, p1);
								break;
							case TBrOpen:
								depthStack.push(TBrClose);
							case TBkOpen:
								depthStack.push(TBkClose);
							case TPOpen:
								depthStack.push(TPClose);
							case TBrClose | TBkClose | TPClose:
								if(depthStack[depthStack.length - 1] != tk) {
									unexpected(tk);
									break;
								}
								depthStack.pop();
								if(depthStack.length == 0)
									break;
							default:
						}
						arr.add(realToken(tk));
					}
				} else {
					var id = "";
					while(true) {
						var c = readChar();
						if( !idents[c] ) {
							readPos--;
							break;
						}
						id += String.fromCharCode(c);
					}
					arr.add(realToken(TId(id)));
				}

				arr.add(realToken(TPClose));
				interpString.push(arr);
				interpolation = false;

				if(arr.length == 2) // If its just ()
					error(EPreset(EMPTY_INTERPOLATION), p1, p1);

				if( StringTools.isEof(peekChar()) )
					break;

				continue;
			}

			var c = readChar();
			if( StringTools.isEof(c) ) {
				line = old;
				error(EUnterminatedString, p1, p1);
				break;
			}

			if( esc ) {
				ce = "\\" + String.fromCharCode(c);
				esc = false;
				switch( c ) {
					case 'n'.code: b.addChar('\n'.code);
					case 'r'.code: b.addChar('\r'.code);
					case 't'.code: b.addChar('\t'.code);
					case "'".code, '"'.code, '\\'.code: b.addChar(c);
					//case '/'.code: // doesnt exist in real haxe
					//	if( allowJSON )
					//		b.addChar(c)
					//	else
					//		invalidChar(c);
					case '0'.code | '1'.code | '2'.code | '3'.code | '4'.code | '5'.code | '6'.code | '7'.code: // Octal \000-\377
						var n = c - '0'.code;
						var i = 0;
						for( i in 0...2 ) { // 2 since we already read the first digit
							var char = readEscape();
							if(char == -1) break;

							n *= 8;
							if( char >= '0'.code && char <= '7'.code ) {
								n += char - '0'.code;
							} else {
								error(EInvalidEscape(ce), p1, p1);
								break;
							}
						}
						b.addChar(n);
					case "x".code: // Hexadecimal \x00-\xFF
						if( !allowJSON ) invalidChar(c);
						var k = 0;
						for( i in 0...2 ) {
							var char = readEscape();
							if(char == -1) break;

							k <<= 4;
							var v = convertHex(char);
							if( v == -1 ) {
								error(EInvalidEscape(ce), p1, p1);
							} else {
								k += v;
							}
						}
						b.addChar(k);
					case "u".code: // Unicode \u0000-\uFFFF | \u{0}-\u{10FFFF}
						if( !allowJSON ) invalidChar(c);
						// todo: rewrite this to use peekChar()
						var nextChar = readChar();
						if( StringTools.isEof(nextChar) ) {
							line = old;
							error(EUnterminatedString, p1, p1);
							break;
						}
						if( nextChar == '{'.code ) { // unicode
							ce += "{";
							var k = 0;
							var i = 0;
							while( true ) {
								var char = readEscape();
								if(char == -1 || char == '}'.code) break;
								if( i > 6 ) {
									error(EInvalidEscape(ce), p1, p1);
									break;
								}

								k <<= 4;
								var v = convertHex(char);
								if( v == -1 ) {
									error(EInvalidEscape(ce), p1, p1);
								} else {
									k += v;
								}
								i++;
							}
							b.addChar(k);
							continue;
						} else {
							readPos--;
						}
						var k = 0;
						for( i in 0...4 ) {
							var char = readEscape();
							if(char == -1) break;

							k <<= 4;
							var v = convertHex(char);
							if( v == -1 ) {
								error(EInvalidEscape(ce), p1, p1);
							} else {
								k += v;
							}
						}
						b.addChar(k);
					default:
						error(EInvalidEscape(ce), p1, p1);
				}
			} else if( c == "\\".code ) {
				esc = true;
			}
			else if( isSingle && c == "$".code) { // Check for $
				var peek = peekChar();
				if(peek != '$'.code) { // make sure it's not escaped
					var valid = false;
					if(interpBlock = (peek == '{'.code)) {
						readPos++; // skip the {
						valid = true;
					} else if(startIdents[peek]) // $ident
						valid = true;

					if(valid) {
						if(interpString == null)
							interpString = [];
						if(b.length > 0) // store the current string
							interpString.push(getTokenList(TConst(CString(b.toString()))));
						b = new StringBuf();
						interpolation = true;
					} else {
						b.addChar(c);
					}
				} else {
					readPos++; // skip the $ from the escaped $$
					b.addChar(c);
				}
			}
			else if( c == until ) // stops when it gets to the same quote character as when it started
				break;
			else {
				if( c == '\n'.code ) line++;
				b.addChar(c);
			}
		}
		if(isSingle && interpString != null && interpString.length > 0) {
			if(b.length > 0)
				interpString.push(getTokenList(TConst(CString(b.toString())))); // Add the current string
			return TInterpString(interpString);
		}
		return TConst( CString(b.toString()) );
	}

	function peekToken():Token {
		var t = token();
		push(t);
		return t;
	}

	function token(/*?infos : Null<haxe.PosInfos>*/) {
		//function ttrace(v:Dynamic, ?infos : Null<haxe.PosInfos>) {
		//	Sys.print(infos.fileName+":"+infos.lineNumber+": " + Std.string(v));
		//	Sys.print("\r\n");
		//}

		#if hscriptPos
		var t = tokens.pop();
		if( t != null ) {
			tokenMin = t.min;
			tokenMax = t.max;
			//trace(t, infos);
			//ttrace(t.t, infos);
			return t.t;
		}
		oldTokenMin = tokenMin;
		oldTokenMax = tokenMax;
		tokenMin = (this.char < 0) ? readPos : readPos - 1;
		var t = _token();
		//ttrace(t, infos);
		tokenMax = (this.char < 0) ? readPos - 1 : readPos - 2;
		return t;
	}

	function _token():Token {
		#else
		if( !tokens.isEmpty() )
			return tokens.pop();
		#end
		var char;
		if( this.char < 0 )
			char = readChar();
		else {
			char = this.char;
			this.char = -1;
		}
		while( true ) {
			if( StringTools.isEof(char) ) {
				this.char = char;
				return TEof;
			}
			switch( char ) {
				case 0:
					return TEof;
				case 32,9,13: // space, tab, CR
					#if hscriptPos
					tokenMin++;
					#end
				case 10: line++; // LF
					#if hscriptPos
					tokenMin++;
					#end
				case 48,49,50,51,52,53,54,55,56,57: // 0...9
					var n = (char - 48) * 1.0;
					var exp = 0.;
					while( true ) {
						char = readChar();
						exp *= 10;
						switch( char ) {
							case 48,49,50,51,52,53,54,55,56,57:
								n = n * 10 + (char - 48);
							case '_'.code:
							case "e".code, "E".code:
								var tk = token();
								var pow : Null<Int> = null;
								switch( tk ) {
									case TConst(CInt(e)): pow = e;
									case TOp("-"):
										tk = token();
										switch( tk ) {
											case TConst(CInt(e)): pow = -e;
											default: push(tk);
										}
									default:
										push(tk);
								}
								if( pow == null )
									invalidChar(char);
								return TConst(CFloat((Math.pow(10, pow) / exp) * n * 10));
							case ".".code:
								if( exp > 0 ) {
									// in case of '0...'
									if( exp == 10 && readChar() == ".".code ) {
										push(TOp("..."));
										var i = Std.int(n);
										return TConst( (i == n) ? CInt(i) : CFloat(n) );
									}
									invalidChar(char);
								}
								exp = 1.;
							case "x".code:
								if( n > 0 || exp > 0 )
									invalidChar(char);
								// read hexa
								var n = 0;
								while( true ) {
									char = readChar();
									switch( char ) {
									case 48,49,50,51,52,53,54,55,56,57: // 0-9
										n = (n << 4) + char - 48;
									case 65,66,67,68,69,70: // A-F
										n = (n << 4) + (char - 55);
									case 97,98,99,100,101,102: // a-f
										n = (n << 4) + (char - 87);
									case '_'.code:
									default:
										this.char = char;
										return TConst(CInt(n));
									}
								}
							case "b".code: // Custom thing, not supported in haxe
								if( n > 0 || exp > 0 )
									invalidChar(char);
								// read binary
								var n = 0;
								while( true ) {
									char = readChar();
									switch( char ) {
										case 48,49: // 0-1
											n = (n << 1) + char - 48;
										case '_'.code:
										default:
											this.char = char;
											return TConst(CInt(n));
									}
								}
							default:
								this.char = char;
								var i = Std.int(n);
								return TConst( (exp > 0) ? CFloat(n * 10 / exp) : ((i == n) ? CInt(i) : CFloat(n)) );
						}
					}
				case ";".code: return TSemicolon;
				case "(".code: return TPOpen;
				case ")".code: return TPClose;
				case ",".code: return TComma;
				case ".".code:
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
						case ".".code:
							char = readChar();
							if( char != ".".code )
								invalidChar(char);
							return TOp("...");
						default:
							this.char = char;
							return TDot;
					}
				case "{".code: return TBrOpen;
				case "}".code: return TBrClose;
				case "[".code: return TBkOpen;
				case "]".code: return TBkClose;
				case "'".code, '"'.code:
					return readString(char, char == "'".code);
				case "?".code:
					char = readChar();
					switch (char) {
						case '?'.code:
							var orp = readPos;
							if (readChar() == '='.code)
								return TOp("??" + "=");

							this.readPos = orp;
							return TOp("??");
						case '.'.code:
							return TQuestionDot;
					}

					this.char = char;
					return TQuestion;
				case ":".code: return TDoubleDot;
				case '='.code:
					char = readChar();
					if( char == '='.code )
						return TOp("==");
					else if ( char == '>'.code )
						return TOp("=>");
					this.char = char;
					return TOp("=");
				case '@'.code:
					char = readChar();
					if( idents[char] || char == ':'.code ) {
						var id = String.fromCharCode(char);
						while( true ) {
							char = readChar();
							if( !idents[char] ) {
								this.char = char;
								return TMeta(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				case '#'.code:
					char = readChar();
					if( idents[char] ) {
						var id = String.fromCharCode(char);
						while( true ) {
							char = readChar();
							if( !idents[char] ) {
								this.char = char;
								return preprocess(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				default:
					if(char == '~'.code) {
						var char = readChar();
						if( char == "/".code ) {
							var regex = getRegexBody();
							var opt = "";
							while( true ) {
								char = readChar();
								if( char != 'g'.code && char != 'i'.code && char != 'm'.code && char != 's'.code && char != 'u'.code ) {
									if( char >= 'a'.code && char <= 'z'.code ) {
										error(ECustom('Invalid regex expression option "' + String.fromCharCode(char) + '"'), readPos, readPos);
									}
									this.char = char;
									return TRegex(regex, opt);
								}
								opt += String.fromCharCode(char);
							}
						}
						readPos--;
						//this.char = peekChar();
					}

					if( ops[char] ) {
						var op = String.fromCharCode(char);
						while( true ) {
							char = readChar();
							if( StringTools.isEof(char) ) char = 0;
							if( !ops[char] ) {
								this.char = char;
								return TOp(op);
							}
							var pop = op;
							op += String.fromCharCode(char);
							if( !opPriority.exists(op) && opPriority.exists(pop) ) {
								if( op == "//" || op == "/*" )
									return tokenComment(op,char);
								this.char = char;
								return TOp(pop);
							}
						}
					}
					if( idents[char] ) {
						var id = String.fromCharCode(char);
						while( true ) {
							char = readChar();
							if( StringTools.isEof(char) ) char = 0;
							if( !idents[char] ) {
								this.char = char;
								if(id == "is") return TOp("is");
								return TId(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
			}
			char = readChar();
		}
		return null;
	}

	function getRegexBody() {
		var regex = new StringBuf();
		var esc = false;
		var start = readPos-2;
		while( true ) {
			var char = readChar();
			if(StringTools.isEof(char))
				error(EUnterminatedRegex, start, start);
			if( char == "\n".code || char == "\r".code )
				error(EUnterminatedRegex, start, readPos-1);

			if( esc ) {
				esc = false;
				switch( char ) {
					case '/'.code: regex.addChar("/".code);
					case 'n'.code: regex.addChar("\n".code);
					case 'r'.code: regex.addChar("\r".code);
					case 't'.code: regex.addChar("\t".code);
					case '\\'.code, '$'.code, '.'.code, '*'.code, '+'.code, '^'.code, '|'.code, '{'.code, '}'.code, '['.code, ']'.code, '('.code, ')'.code, '?'.code, '-'.code:
						regex.addChar(char);
					case '0'.code | '1'.code | '2'.code | '3'.code | '4'.code | '5'.code | '6'.code | '7'.code | '8'.code | '9'.code:
						regex.addChar("\\".code);
						regex.addChar(char);
					case 'w'.code, 'W'.code, 'b'.code, 'B'.code, 's'.code, 'S'.code, 'd'.code, 'D'.code, 'x'.code:
						regex.addChar("\\".code);
						regex.addChar(char);
					case 'u'.code, 'U'.code: // UNICODE
						regex.addChar("\\".code);
						for( i in 0...4 ) {
							var c = readChar();
							if( StringTools.isEof(c) )
								error(EUnterminatedRegex, start, readPos-1);
							var h = convertHex(c);
							if( h == -1 )
								invalidChar(c);
							regex.addChar(c);
						}

					default: invalidChar(char);
				}
			} else if( char == "\\".code ) {
				esc = true;
				continue;
			} else if( char == "/".code )
				break;
			else
				regex.addChar(char);
		}
		return regex.toString();
	}

	function preprocValue( id : String ) : Dynamic {
		return preprocesorValues.get(id);
	}

	var preprocStack : Array<{ r : Bool }>;

	function parsePreproCond():Expr {
		var tk = token();
		return switch( tk ) {
			case TPOpen:
				push(TPOpen);
				parseExpr();
			case TId(id):
				while(true) {
					var tk = token();
					if(tk == TDot) {
						id += ".";
						tk = token();
						switch(tk) {
							case TId(id2):
								id += id2;
							default: unexpected(tk);
						}
					} else {
						push(tk);
						break;
					}
				}
				mk(EIdent(id), tokenMin, tokenMax);
			case TOp("!"):
				mk(EUnop(OpNot, true, parsePreproCond()), tokenMin, tokenMax);
			default:
				unexpected(tk);
		}
	}

	function getValFromExpr( e : Expr, ?waitFloat:Bool ):Dynamic
	{
		var edef:ExprDef = expr(e);
		switch( edef )
		{
			case EParent(e):
				return getValFromExpr(e, waitFloat);
			case EIdent(id):
				return preprocValue(id);
			case EConst(c):
				switch (c) {
					case CInt(v): return waitFloat || convertPreProcValsToStr ? Std.string(v) : v;
					case CFloat(f): return waitFloat || convertPreProcValsToStr ? Std.string(f) : f;
					case CString(s): return s;
				}
			case ECall(expr(_) => EIdent("version"), expr(_[0]) => EConst(CString(s))): // this thing exists lol
				return s;
			// ?todo: allow more
			default:
				error(EInvalidPreprocessor(edef.getName()), readPos, readPos);
				return null;
		}
	}

	function evalPreproCond( e : Expr ):Bool {
		// trace(Printer.toString(e));
		var edef:ExprDef = expr(e);
		switch( edef ) {
			case EIdent(id):
				return preprocValue(id) != null;
			case EField(e2, f):
				switch(expr(e2)) {
					case EIdent(id):
						return preprocValue(id + "." + f) != null;
					case edef2:
						error(EInvalidPreprocessor("Can't eval " + edef.getName() + " with " + edef2.getName()), readPos, readPos);
						return false;
				}
			case EUnop(OpNot, _, e):
				return !evalPreproCond(e);
			case EParent(e):
				return evalPreproCond(e);
			case EBinop(op, e1, e2):
				switch (op)
				{
					case OpBoolAnd:
						return evalPreproCond(e1) && evalPreproCond(e2);
					case OpBoolOr:
						return evalPreproCond(e1) || evalPreproCond(e2);
					case OpEq:
						return getValFromExpr(e1) == getValFromExpr(e2);
					case OpNotEq:
						return getValFromExpr(e1) != getValFromExpr(e2);
					case OpGte:
						return getValFromExpr(e1, true) >= getValFromExpr(e2, true);
					case OpGt:
						return getValFromExpr(e1, true) > getValFromExpr(e2, true);
					case OpLte:
						return getValFromExpr(e1, true) >= getValFromExpr(e2, true);
					case OpLt:
						return getValFromExpr(e1, true) > getValFromExpr(e2, true);
					default:
						error(EInvalidPreprocessor('Uncorrected operator \'$op\''), readPos, readPos);
						return false;
				}
				/*
				var define = preprocesorValues.get(e1);
				var expr2 = expr(e2);
				return define != null && define == switch (expr2){case EIdent(id): id default: evalPreproCond(expr2)};
				*/
			default:
				error(EInvalidPreprocessor("Can't eval " + edef.getName()), readPos, readPos);
				return false;
		}
	}

	function preprocess( id : String ) : Token {
		switch( id ) {
			case "if":
				var e = parsePreproCond();
				if( evalPreproCond(e) ) {
					preprocStack.push({ r : true });
					return token();
				}
				preprocStack.push({ r : false });
				skipTokens();
				return token();
			case "else", "elseif" if( preprocStack.length > 0 ):
				if( preprocStack[preprocStack.length - 1].r ) {
					preprocStack[preprocStack.length - 1].r = false;
					skipTokens();
					return token();
				} else if( id == "else" ) {
					preprocStack.pop();
					preprocStack.push({ r : true });
					return token();
				} else {
					// elseif
					preprocStack.pop();
					return preprocess("if");
				}
			case "end" if( preprocStack.length > 0 ):
				preprocStack.pop();
				return token();
			default:
				return TPrepro(id);
		}
	}

	inline function getTk(t:StoredToken) {
		#if hscriptPos
		return t.t;
		#else
		return t;
		#end
	}

	function skipTokens() {
		var spos = preprocStack.length - 1;
		var obj = preprocStack[spos];
		var pos = readPos;
		var tk:Token;
		while( true ) {
			tk = token();
			if( tk == TEof )
			{
				if (preprocStack.length != 0)
				{
					error(EInvalidPreprocessor("Unclosed"), pos, pos);
				}
				else
				{
					break;
				}
			}

			if( preprocStack[spos] != obj ) {
				push(tk);
				break;
			}
		}
	}

	function tokenComment( op : String, char : Int ):Token {
		var c = op.charCodeAt(1);
		var s = input;
		if( c == '/'.code ) { // comment
			while( char != '\r'.code && char != '\n'.code ) {
				char = readChar();
				if( StringTools.isEof(char) ) break;
			}
			this.char = char;
			return token();
		}
		if( c == '*'.code ) { /* comment */
			var old = line;
			if( op == "/**/" ) {
				this.char = char;
				return token();
			}
			while( true ) {
				while( char != '*'.code ) {
					if( char == '\n'.code ) line++;
					char = readChar();
					if( StringTools.isEof(char) ) {
						line = old;
						error(EUnterminatedComment, tokenMin, tokenMin);
						break;
					}
				}
				char = readChar();
				if( StringTools.isEof(char) ) {
					line = old;
					error(EUnterminatedComment, tokenMin, tokenMin);
					break;
				}
				if( char == '/'.code )
					break;
			}
			return token();
		}
		this.char = char;
		return TOp(op);
	}

	function constString( c ) {
		return switch(c) {
			case CInt(v): Std.string(v);
			case CFloat(f): Std.string(f);
			case CString(s): '"' + s + '"'; // TODO : escape + quote
			#if !haxe3
			case CInt32(v): Std.string(v);
			#end
		}
	}

	function constInterpString( s:Array<TokenList> ) {
		var b = new StringBuf();
		for(t in s)
			for(tk in t)
				b.add(tokenString(getTk(tk)));
		return b.toString();
	}

	function tokenString( t:Token ):String {
		return switch( t ) {
			case TEof: "<eof>";
			case TConst(c): constString(c);
			case TInterpString(tg): constInterpString(tg);
			case TRegex(r, opt): '~/' + r + '/' + opt;
			case TId(s) | TOp(s): s;
			case TPOpen: "(";
			case TPClose: ")";
			case TBrOpen: "{";
			case TBrClose: "}";
			case TDot: ".";
			case TQuestionDot: "?.";
			case TComma: ",";
			case TSemicolon: ";";
			case TBkOpen: "[";
			case TBkClose: "]";
			case TQuestion: "?";
			case TDoubleDot: ":";
			case TMeta(id): "@" + id;
			case TPrepro(id): "#" + id;
		}
	}

}
