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
	EConst( c : Const ); // Const int, flaot and string
	EIdent( v : String ); // get variable
	EVar( n : String, ?t : CType, ?e : Expr, ?isPublic : Bool, ?isStatic : Bool, ?isPrivate : Bool, ?isFinal : Bool, ?isInline : Bool ); // init var (var a:Float = 5;)
	EParent( e : Expr ); // ( expr )
	EBlock( e : Array<Expr> ); // { expr }
	EField( e : Expr, f : String , ?safe : Bool ); // var.field
	EBinop( op : String, e1 : Expr, e2 : Expr ); // var == 0, var >= 5
	EUnop( op : String, prefix : Bool, e : Expr ); // !var, var++
	ECall( e : Expr, params : Array<Expr> ); // myFunction(5, 6)
	EIf( cond : Expr, e1 : Expr, ?e2 : Expr ); // if (var == 5){ expr } else { expr }
	EWhile( cond : Expr, e : Expr ); // while (var == 5) { expr }
	EFor( v : String, it : Expr, e : Expr, ?ithv: String); // for (i in 0...8) { expr }
	EBreak; // break
	EContinue; // continue
	EFunction( args : Array<Argument>, e : Expr, ?name : String, ?ret : CType, ?isPublic : Bool, ?isStatic : Bool, ?isOverride : Bool, ?isPrivate : Bool, ?isFinal : Bool, ?isInline : Bool ); // init function (function(argA, argB:Float) { expr } or (argA, argB:Float) -> { expr })
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
	ECheckType( e : Expr, t : CType ); // (dynamic : FlxSprite)

	EImport( c : String, ?asname:String ); // import flixel.FlxSprite as Sprite;
	EImportStar( c : String ); // import flixel.*;
	EUsing( c : String ); // using StringTools;
	EClass( name:String, fields:Array<Expr>, ?extend:String, interfaces:Array<String>, ?isFinal:Bool, ?isPrivate:Bool ); // Class MyClass { expr }
}

@:structInit
final class SwitchCase {
	public var values : Array<Expr>;
	public var expr : Expr;
}

typedef Argument = { name : String, ?t : CType, ?opt : Bool, ?value : Expr };

typedef Metadata = Array<{ name : String, params : Array<Expr> }>;

enum CType {
	CTPath( path : Array<String>, ?params : Array<CType> );
	CTFun( args : Array<CType>, ret : CType );
	CTAnon( fields : Array<{ name : String, t : CType, ?meta : Metadata }> );
	CTParent( t : CType );
	CTOpt( t : CType );
	CTNamed( n : String, t : CType );
}

#if hscriptPos
class Error {
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
enum Error {
#end
	EInvalidChar( c : Int );
	EUnexpected( s : String );
	EUnterminatedString;
	EUnterminatedComment;
	EInvalidPreprocessor( msg : String );
	EUnknownVariable( v : String );
	EInvalidIterator( v : String );
	EInvalidOp( op : String );
	EInvalidAccess( f : String );
	ECustom( msg : String );
	EInvalidClass( className : String);
	EAlreadyExistingClass( className : String);
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
