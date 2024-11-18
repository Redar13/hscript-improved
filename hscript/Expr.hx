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

typedef Int8 = #if cpp cpp.Int8 #elseif cs cs.Int8 #elseif java java.Int8 #else Int #end;
typedef Int16 = #if cpp cpp.Int16 #elseif cs cs.Int16 #elseif java java.Int16 #else Int #end;
typedef Int32 = #if cpp cpp.Int32 #else Int #end;
typedef Int64 = #if cpp cpp.Int64 #elseif cs cs.Int64 #elseif java java.Int64 #else Int  Int #end;

typedef UInt8 = #if cpp cpp.UInt8 #elseif cs cs.UInt8 #else Int #end;
typedef UInt16 = #if cpp cpp.UInt16 #elseif cs cs.UInt16 #else Int #end;
typedef UInt32 = #if cpp cpp.UInt32 #else Int #end;
typedef UInt64 = #if cpp cpp.UInt64 #else Int #end;

enum Const {
	CInt( v : Int );
	CFloat( f : Float );
	CString( s : String );
}

#if hscriptPos
@:structInit
final class Expr {
	public var e : ExprDef;
	public var pmin : Int;
	public var pmax : Int;
	public var origin : String;
	public var line : Int;
}
enum ExprDef {
#else
typedef ExprDef = Expr;
enum Expr {
#end
	EConst( c : Const ); // Const int, float and string
	EIdent( v : String ); // variable referense
	EVar( n : String, ?t : CType, ?e : Expr, ?access : EFieldAccess); // var a;
	EParent( e : Expr ); // ( expr )
	EBlock( e : Array<Expr> ); // { expr }
	EField( e : Expr, f : String , ?safe : Bool ); // var.field
	EBinop( op : Binop, e1 : Expr, e2 : Expr ); // var == 0, var >= 5
	EUnop( op : Unop, prefix : Bool, e : Expr ); // !var, var++
	ECall( e : Expr, params : Array<Expr> ); // myFunction(5, 6)
	EIf( cond : Expr, e1 : Expr, ?e2 : Expr ); // if (var == 5){ expr } else { expr }
	EWhile( cond : Expr, e : Expr ); // while (var == 5) { expr }
	EFor( v : String, it : Expr, e : Expr, ?ithv: String); // for (i in 0...8) { expr }
	EBreak; // break
	EContinue; // continue
	EFunction( args : Array<Argument>, e : Expr, ?name : String, ?ret : CType, ?access : EFieldAccess); // function(argA, argB:Float) { expr } or (argA, argB:Float) -> { expr }
	EReturn( ?e : Expr ); // function() { return 0; }
	EArray( e : Expr, index : Expr ); // myArray[0]
	EArrayDecl( e : Array<Expr>, ?wantedType: CType ); // [1, 2, 3, 4, 5]
	ENew( cl : String, params : Array<Expr> ); // new MyClass(5, 8)
	EThrow( e : Expr ); // throw "Err";
	ETry( e : Expr, v : String, t : Null<CType>, ecatch : Expr ); // try { expr } catch(e) { expr }
	EObject( fl : Array<{ name : String, e : Expr }> ); // { a: 5, b: 7, c: 4}
	ETernary( cond : Expr, e1 : Expr, e2 : Expr ); // a == true ? expr : expr
	ESwitch( e : Expr, cases : Array<SwitchCase>, ?defaultExpr : Expr ); // switch(e) { case 5: expr default: expr}
	EDoWhile( cond : Expr, e : Expr); // do { expr } while (var == 5)
	EMeta( name : String, args : Array<Expr>, e : Expr ); // @:access(flixel.FlxG)
	ECheckType( e : Expr, t : CType ); // (dynamicVar : FlxSprite)

	EImport( c : String, ?asname:String ); // import flixel.FlxSprite as Sprite;
	EImportStar( c : String ); // import flixel.*;
	EUsing( c : String ); // using StringTools;
	EClass( name:String, fields:Array<Expr>, ?extend:String, ?interfaces:Array<String>, ?isFinal:Bool, ?isPrivate:Bool ); // Class MyClass { expr }
}

enum Binop {
	/**
		`+`
	**/
	OpAdd;

	/**
		`*`
	**/
	OpMult;

	/**
		`/`
	**/
	OpDiv;

	/**
		`-`
	**/
	OpSub;

	/**
		`=`
	**/
	OpAssign;

	/**
		`==`
	**/
	OpEq;

	/**
		`!=`
	**/
	OpNotEq;

	/**
		`>`
	**/
	OpGt;

	/**
		`>=`
	**/
	OpGte;

	/**
		`<`
	**/
	OpLt;

	/**
		`<=`
	**/
	OpLte;

	/**
		`&`
	**/
	OpAnd;

	/**
		`|`
	**/
	OpOr;

	/**
		`^`
	**/
	OpXor;

	/**
		`&&`
	**/
	OpBoolAnd;

	/**
		`||`
	**/
	OpBoolOr;

	/**
		`<<`
	**/
	OpShl;

	/**
		`>>`
	**/
	OpShr;

	/**
		`>>>`
	**/
	OpUShr;

	/**
		`%`
	**/
	OpMod;

	/**
		`+=` `-=` `/=` `*=` `<<=` `>>=` `>>>=` `|=` `&=` `^=` `%=`
	**/
	OpAssignOp(op:Binop);

	/**
		`...`
	**/
	OpInterval;

	/**
		`=>`
	**/
	OpArrow;

	/**
		`is`
	**/
	OpIs; // used to be OpIn, but our system treats that differently

	/**
		`??`
	**/
	OpNullCoal;
}

enum abstract Unop(UInt8) {
	/**
		`++`
	**/
	var OpIncrement;

	/**
		`--`
	**/
	var OpDecrement;

	/**
		`!`
	**/
	var OpNot;

	/**
		`-`
	**/
	var OpNeg;

	/**
		`~`
	**/
	var OpNegBits;

	/**
		`...`
	**/
	var OpSpread;
}

@:structInit
final class SwitchCase {
	public var values : Array<Expr>;
	public var expr : Expr;
}

// typedef Argument = { name : String, ?t : CType, ?opt : Bool, ?value : Expr };
class Argument {
	public var name : String;
	public var t : Null<CType>;
	public var opt : Bool;
	public var value : Null<Expr>;
	public function new(name:String, ?t:Null<CType>, ?opt:Bool, ?value:Expr) {
		this.name = name;
		this.t = t;
		this.opt = opt;
		this.value = value;
	}

	public function toString() {
		return (opt ? "?" : "") + name + (t != null ? ":" + Printer.convertTypeToString(t) : "") + (value != null ? "=" + Printer.convertExprToString(value) : "");
	}
}

typedef Metadata = Array<{ name : String, params : Array<Expr> }>;

enum abstract EFieldAccess(UInt16) from UInt16 to UInt16 {
	public function new(?isPublic:Bool, ?isInline:Bool, ?isOverride:Bool, ?isStatic:Bool, ?isFinal:Bool, ?isMacro:Bool) {
		this = isPublic ? 1 : 0;
		if (isInline) {
			this += 0x10;
		}
		if (isOverride) {
			this += 0x100;
		} else if (isStatic) {
			this += 0x200;
		} else if (isMacro) {
			this += 0x300;
		}
		if (isFinal) {
			this += 0x1000;
		}
	}

	public var isPrivate(get, set):Bool;
	public var isPublic(get, set):Bool;
	public var isInline(get, set):Bool;
	public var isOverride(get, set):Bool;
	public var isStatic(get, set):Bool;
	public var isMacro(get, set):Bool;
	public var isFinal(get, set):Bool;

	inline function get_isPrivate():Bool {
		return this & 0x0001 == 0;
	}

	inline function set_isPrivate(e):Bool {
		if (e)
			this |= 0x0000;
		else
			this &= 0xFFF1;
		return e;
	}

	inline function get_isPublic():Bool {
		return this & 0x0001 == 1;
	}

	inline function set_isPublic(e):Bool {
		if (e)
			this |= 0x0001;
		else
			this &= 0xFFF0;
		return e;
	}

	inline function get_isInline():Bool {
		return this & 0x0010 == 0x0010;
	}

	inline function set_isInline(e):Bool {
		if (e)
			this |= 0x0010;
		else
			this &= 0xFF0F;
		return e;
	}

	inline function get_isOverride():Bool {
		return this & 0x0300 == 0x0100;
	}

	inline function set_isOverride(e):Bool {
		specialHexCode(e, isStatic, isMacro);
		return e;
	}

	inline function get_isStatic():Bool {
		return this & 0x0300 == 0x0200 || isMacro; // you can't have a macro without static
	}

	inline function set_isStatic(e):Bool {
		specialHexCode(isOverride, e, isMacro);
		return e;
	}

	inline function get_isMacro():Bool {
		return this & 0x0300 == 0x0300;
	}

	inline function set_isMacro(e):Bool {
		specialHexCode(isOverride, isStatic, e);
		return e;
	}

	inline function get_isFinal():Bool {
		return this & 0x1000 == 0x1000;
	}

	inline function set_isFinal(e):Bool {
		if (e)
			this |= 0x1000;
		else
			this &= 0x0FFF;
		return e;
	}

	extern inline function specialHexCode(needOverride:Bool, needStatic:Bool, needMacro:Bool) {
		this &= 0xF0FF;
		if (needOverride)
			this |= 0x0100;
		else if (needStatic)
			this |= 0x0200;
		else if (needMacro)
			this |= 0x0300;
	}

	public static function toStringExtr(acc:EFieldAccess, ?allowFinal:Bool):String {
		var res = "";
		if (allowFinal && acc.isFinal)
			res += " final";
		if (acc.isPublic)
			res += " public";
		// else
		// 	res += " private";
		if (acc.isOverride)
			res += " override";
		else if (acc.isStatic)
			res += " static";
		if (acc.isMacro)
			res += " macro";
		if (acc.isInline)
			res += " inline";
		return res.length > 0 ? res.substr(1) : res;
	}

	public function toString():String {
		return inline toStringExtr(this);
	}
}

enum CType {
	CTPath( path : Array<String>, ?params : Array<CType> );
	CTFun( args : Array<CType>, ret : CType );
	CTAnon( fields : Array<{ name : String, t : CType, ?meta : Metadata }> );
	CTParent( t : CType );
	CTOpt( t : CType );
	CTNamed( n : String, t : CType );
}

typedef Error = Error_;

#if hscriptPos
class Error_ {
	public var e : ErrorDef;
	public var pmin : Int;
	public var pmax : Int;
	public var origin : String;
	public var line : Int;
	public function new(e, pmin, pmax, origin, line) {
		this.e = e;
		this.pmin = pmin;
		this.pmax = pmax;
		this.origin = origin;
		this.line = line;
	}
	public function toString(): String {
		return Printer.errorToString(this);
	}
}
enum ErrorDef {
#else
enum Error_ {
#end
	EInvalidChar( c : Int );
	EUnexpected( s : String );
	EUnterminatedString;
	EUnterminatedComment;
	EUnterminatedRegex;
	EInvalidPreprocessor( msg : String );
	EUnknownVariable( v : String );
	EInvalidIterator( v : String );
	EInvalidType( t : String );
	EInvalidOp( op : String );
	EInvalidAccess( f : String, ?on : String );
	ECustom( msg : String );
	EPreset( msg : ErrorMessage );
	EInvalidClass( className : String);
	EAlreadyExistingClass( className : String);
	EInvalidEscape( s : String );
}

enum abstract ErrorMessage(Expr.UInt8) from Expr.UInt8 to Expr.UInt8 {
    final INVALID_CHAR_CODE_MULTI;
    final FROM_CHAR_CODE_NON_INT;
    final EMPTY_INTERPOLATION;
    final UNKNOWN_MAP_TYPE;
    final UNKNOWN_MAP_TYPE_RUNTIME;
    final EXPECT_KEY_VALUE_SYNTAX;

    public function toString():String {
        return switch(cast this) {
            case INVALID_CHAR_CODE_MULTI: "'char'.code only works on single characters";
            case FROM_CHAR_CODE_NON_INT: "String.fromCharCode only works on integers";
            case EMPTY_INTERPOLATION: "Invalid interpolation: Expression cannot be empty";
            case UNKNOWN_MAP_TYPE: "Unknown Map Type";
            case UNKNOWN_MAP_TYPE_RUNTIME: "Unknown Map Type, while parsing at runtime";
            case EXPECT_KEY_VALUE_SYNTAX: "Expected a => b";
        }
    }
}

enum ModuleDecl {
	DPackage( path : Array<String> );
	DImport( path : Array<String>, ?everything : Bool );
	DClass( c : ClassDecl );
	DTypedef( c : TypeDecl );
}

typedef ModuleType = {
	var name : String;
	var params : {}; // TODO : not yet parsed
	var meta : Metadata;
	var isPrivate : Bool;
}

typedef ClassDecl = {> ModuleType,
	var extend : Null<CType>;
	var implement : Array<CType>;
	var fields : Array<FieldDecl>;
	var isExtern : Bool;
}

typedef TypeDecl = {> ModuleType,
	var t : CType;
}

typedef FieldDecl = {
	var name : String;
	var meta : Metadata;
	var kind : FieldKind;
	var access : Array<FieldAccess>;
}

enum abstract FieldAccess(UInt8) {
	var APublic;
	var APrivate;
	var AInline;
	var AOverride;
	var AStatic;
	var AMacro;
}

enum FieldKind {
	KFunction( f : FunctionDecl );
	KVar( v : VarDecl );
}

typedef FunctionDecl = {
	var args : Array<Argument>;
	var expr : Expr;
	var ret : Null<CType>;
}

typedef VarDecl = {
	var get : Null<String>; // TODO
	var set : Null<String>; // TODO
	var expr : Null<Expr>;
	var type : Null<CType>;
}
