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

/*
 * YoshiCrafter Engine fixes:
 * - Added Error handler
 * - Added Imports
 * - Added @:bypassAccessor
 */
package hscript;

import haxe.Constraints.Function;
import haxe.display.Protocol.InitializeResult;
import haxe.iterators.StringKeyValueIteratorUnicode;
import haxe.EnumTools;
import haxe.PosInfos;
import haxe.Constraints.IMap;
import hscript.custom_classes.PolymodAbstractScriptClass;
import hscript.custom_classes.PolymodClassDeclEx;
import hscript.custom_classes.PolymodScriptClass;
import hscript.macros.ClassTools;
import hscript.Expr;
import hscript.HScriptedClass;
import hscript.UnsafeReflect;

using StringTools;

enum abstract ScriptObjectType(UInt8) {
	var SClass;
	var SObject;
	var SStaticClass;
	var SCustomClass;
	var SBehaviourClass;
	var SNull;

	@:to
	function toString():String {
		return switch (cast this) {
			case SClass: "SClass";
			case SObject: "SObject";
			case SStaticClass: "SStaticClass";
			case SCustomClass: "SCustomClass";
			case SBehaviourClass: "SBehaviourClass";
			default: "SNull";
		}
	}
}

@:structInit
class DeclaredVar {
	public var r:Dynamic;
	public var depth:Int;

	function toString()
		return '{r:$r, depth:$depth}';
}

@:structInit
class RedeclaredVar {
	public var n:String;
	public var old:DeclaredVar;
	public var depth:Int;

	function toString()
		return '{n$n, depth:$depth, old: $old}';
}

private enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

typedef HXStringMap<T> = #if haxe3 Map<String, T> #else Hash<T> #end;

@:access(hscript.HScriptedClass)
class Interp {
	public var scriptObject(default, set):Dynamic;

	private var _hasScriptObject(default, null):Bool = false;
	private var _scriptObjectType(default, null):ScriptObjectType = SNull;

	function set_scriptObject(v:Dynamic) {
		switch (Type.typeof(v)) {
			case TClass(c): // Class Access
				__instanceFields = Type.getInstanceFields(c);
				if (Std.isOfType(v, HScriptedClass)) {
					__instanceFields = __instanceFields.filter(str -> return str.indexOf("__hsx_super_") != 0);
					if (_proxy != null)
						_proxy.__superClassFieldList = __instanceFields;
					// __instanceFields.remove("_asc");

					// __instanceFields = Type.getInstanceFields(Reflect.field(cast(v, HScriptedClass), "_asc."))
					// var v = cast(v, HScriptedClass);
					// var classFields = v.__class__fields;
					// if(classFields != null)
					// 	__instanceFields = __instanceFields.concat(classFields);
					_scriptObjectType = SCustomClass;
				} else if (Std.isOfType(c, IHScriptCustomBehaviour)) {
					_scriptObjectType = SBehaviourClass;
				} else {
					_scriptObjectType = SClass;
				}
			case TObject: // Object Access or Static Class Access
				var cls = Type.getClass(v);
				switch (Type.typeof(cls)) {
					case TClass(c): // Static Class Access
						__instanceFields = Type.getInstanceFields(c);
						if (Std.isOfType(c, HScriptedClass)) {
							__instanceFields = __instanceFields.filter(str -> return str.indexOf("__hsx_super_") != 0);
							if (_proxy != null)
								_proxy.__superClassFieldList = __instanceFields;
							// __instanceFields = Type.getInstanceFields(c).filter(str -> return str.indexOf("__hsx_super_") != 0);
							// __instanceFields = Type.getInstanceFields(Reflect.field(cast(v, HScriptedClass), "_asc."))
							// var v = cast(v, HScriptedClass);
							// var classFields = v.__class__fields;
							// if(classFields != null)
							// 	__instanceFields = __instanceFields.concat(classFields);
							_scriptObjectType = SCustomClass;
						} else {
							_scriptObjectType = SStaticClass;
						}
					default: // Object Access
						__instanceFields = UnsafeReflect.fields(v);
						_scriptObjectType = SObject;
				}
			default: // Null or other
				__instanceFields = [];
				_scriptObjectType = SNull;
		}
		// trace(_scriptObjectType);
		// trace(__instanceFields);
		_hasScriptObject = _scriptObjectType != SNull;
		return scriptObject = v;
	}

	public var parentInterp(default, set):Interp;

	function set_parentInterp(v:Interp):Interp {
		if (parentInterp != null) {
			errorHandler = null;
			importFailedCallback = null;
			usingClasses = null;
			onMetadata = null;
			// staticVariables = null;
			allowStaticVariables = allowPublicVariables = allowTypes = false;
			#if hscriptPos
			variables.set("trace", UnsafeReflect.makeVarArgs(function(el) {
				var inf = posInfos();
				var v = el.shift();
				if (el.length > 0)
					inf.customParams = el;
				haxe.Log.trace(Std.string(v), inf);
			}));
			#end
		}
		parentInterp = v;
		if (parentInterp != null) {
			errorHandler = parentInterp.errorHandler;
			importFailedCallback = parentInterp.importFailedCallback;
			onMetadata = parentInterp.onMetadata;
			// staticVariables = parentInterp.staticVariables;
			allowStaticVariables = parentInterp.allowStaticVariables;
			allowPublicVariables = parentInterp.allowPublicVariables;
			allowTypes = parentInterp.allowTypes;
			usingClasses = parentInterp.usingClasses;
			usingEnabled = parentInterp.usingEnabled;
			#if hscriptPos
			var me = this;
			variables.set("trace", UnsafeReflect.makeVarArgs(function(el) {
				var oldExpr = parentInterp.curExpr;
				var curExpr = me.curExpr;
				parentInterp.curExpr = curExpr;
				UnsafeReflect.callMethod(null, parentInterp.variables.get("trace"), el);
				parentInterp.curExpr = oldExpr;
			}));
			#end
		}
		return parentInterp;
	}

	public var errorHandler:Error->Void;
	public var importFailedCallback:Array<String>->Bool;
	public var onMetadata:String->Array<Expr>->Expr->Dynamic;
	public var customClasses:HXStringMap<Dynamic>;
	public var variables:HXStringMap<Dynamic>;
	public var usingClasses:List<Class<Dynamic>>;
	public var publicVariables:HXStringMap<Dynamic>;
	public var staticVariables:HXStringMap<Dynamic>;

	public var locals:HXStringMap<DeclaredVar>;

	var binops:HXStringMap<Expr->Expr->Dynamic>;

	var depth:Int = 0;
	var inTry:Bool;
	var declared:Array<RedeclaredVar>;
	var returnValue:Dynamic;

	var isBypassAccessor:Bool = false;

	public var usingEnabled:Bool = true;
	public var importEnabled:Bool = true;

	public var allowStaticVariables:Bool = false;
	public var allowPublicVariables:Bool = false;
	public var allowTypes:Bool = false;

	public var importBlocklist:Array<String> = [
		// "flixel.FlxG"
	];

	var __staticId:String;
	var __instanceFields:Array<String> = [];
	#if hscriptPos
	var curExpr:Expr;
	#end

	var _proxy:PolymodAbstractScriptClass = null;

	public function new(?targetObj:Dynamic) {
		locals = new HXStringMap();
		declared = new Array();
		resetVariables();
		initOps();
		if (targetObj == null)
			scriptObject = targetObj;
	}

	private function resetVariables() {
		usingClasses = new List<Class<Dynamic>>();
		customClasses = new HXStringMap<Dynamic>();
		variables = new HXStringMap<Dynamic>();
		publicVariables = new HXStringMap<Dynamic>();
		staticVariables = new HXStringMap<Dynamic>();

		variables.set("null", null);
		variables.set("true", true);
		variables.set("false", false);
		variables.set("trace", UnsafeReflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if (el.length > 0)
				inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function posInfos():PosInfos {
		#if hscriptPos
		if (curExpr != null)
			return cast {fileName: curExpr.origin, lineNumber: curExpr.line};
		#end
		return cast {fileName: "hscript", lineNumber: 0};
	}

	function initOps() {
		var me = this;
		binops = new HXStringMap();
		binops.set("+", function(e1, e2) return me.expr(e1) + me.expr(e2));
		binops.set("-", function(e1, e2) return me.expr(e1) - me.expr(e2));
		binops.set("*", function(e1, e2) return me.expr(e1) * me.expr(e2));
		binops.set("/", function(e1, e2) return me.expr(e1) / me.expr(e2));
		binops.set("%", function(e1, e2) return me.expr(e1) % me.expr(e2));
		binops.set("&", function(e1, e2) return me.expr(e1) & me.expr(e2));
		binops.set("|", function(e1, e2) return me.expr(e1) | me.expr(e2));
		binops.set("^", function(e1, e2) return me.expr(e1) ^ me.expr(e2));
		binops.set("<<", function(e1, e2) return me.expr(e1) << me.expr(e2));
		binops.set(">>", function(e1, e2) return me.expr(e1) >> me.expr(e2));
		binops.set(">>>", function(e1, e2) return me.expr(e1) >>> me.expr(e2));
		binops.set("==", function(e1, e2) return me.expr(e1) == me.expr(e2));
		binops.set("!=", function(e1, e2) return me.expr(e1) != me.expr(e2));
		binops.set(">=", function(e1, e2) return me.expr(e1) >= me.expr(e2));
		binops.set("<=", function(e1, e2) return me.expr(e1) <= me.expr(e2));
		binops.set(">", function(e1, e2) return me.expr(e1) > me.expr(e2));
		binops.set("<", function(e1, e2) return me.expr(e1) < me.expr(e2));
		binops.set("||", function(e1, e2) return me.expr(e1) == true || me.expr(e2) == true);
		binops.set("&&", function(e1, e2) return me.expr(e1) == true && me.expr(e2) == true);
		binops.set("is", checkIsType);
		binops.set("=", assign);
		binops.set("??", function(e1, e2) {
			var expr1:Dynamic = me.expr(e1);
			return expr1 == null ? me.expr(e2) : expr1;
		});
		binops.set("...", function(e1, e2) return new
			#if (haxe_211 || haxe3)
			IntIterator
			#else
			IntIter
			#end(me.expr(e1), me.expr(e2)));
		assignOp("+=", function(v1:Dynamic, v2:Dynamic) return v1 + v2);
		assignOp("-=", function(v1:Float, v2:Float) return v1 - v2);
		assignOp("*=", function(v1:Float, v2:Float) return v1 * v2);
		assignOp("/=", function(v1:Float, v2:Float) return v1 / v2);
		assignOp("%=", function(v1:Float, v2:Float) return v1 % v2);
		assignOp("&=", function(v1, v2) return v1 & v2);
		assignOp("|=", function(v1, v2) return v1 | v2);
		assignOp("^=", function(v1, v2) return v1 ^ v2);
		assignOp("<<=", function(v1, v2) return v1 << v2);
		assignOp(">>=", function(v1, v2) return v1 >> v2);
		assignOp(">>>=", function(v1, v2) return v1 >>> v2);
		assignOp("??" + "=", function(v1, v2) return v1 == null ? v2 : v1);
	}

	function castExprByType(expr:Dynamic, ?type:CType):Dynamic {
		if (!allowTypes || type == null)
			return expr;
		// trace(type);
		switch (type) {
			case CTPath(t, paramas):
				var strType = t[0];
				switch (strType) {
					case "Array":
						if (!Std.isOfType(expr, Array))
							error(EUnexpected(strType));
						return expr;
					case "Class":
						if (!Std.isOfType(expr, Class))
							error(EUnexpected(strType));
						return expr;
					case "Float":
						if (!Std.isOfType(expr, Float))
							error(EUnexpected(strType));
						return expr;
					case "Int":
						if (!Std.isOfType(expr, Int))
							error(EUnexpected(strType));
						return expr;
					case "Bool":
						if (!Std.isOfType(expr, Bool))
							error(EUnexpected(strType));
						return expr;
					case "String":
						if (!Std.isOfType(expr, String))
							error(EUnexpected(strType));
						return expr;
					case "Null":
						return expr == null || paramas == null || paramas.length == 0 ? null : castExprByType(expr, paramas[0]);
					case("Map" | "IMap"):
						if (!Std.isOfType(expr, IMap))
							error(ECustom(strType));
						return expr;
					// case StringTools.trim(_).length == 0:
					// 	expr;
					case "Void":
						if (expr != null)
							error(ECustom(strType));
						return expr;
					default:
						if (customClasses.exists(strType)) {
							if (Std.isOfType(expr, HScriptedClass)) {
								if (UnsafeReflect.field(expr, "_asc").name == strType)
									return expr;
							}
							error(EUnexpected(strType));
							return null;
						}
						if (strType.length > 1)
							strType = t.join(".");
						var exprType = resolve(strType);
						// if (exprType != null && !Std.isOfType(expr, exprType))
						// 	return null;
						if (exprType != null && !Std.isOfType(expr, exprType) && (exprType is Class && expr != null))
							error(EUnexpected(strType));
						return expr;
				}
			default:
				/*
					var exprType:Dynamic = expr(e2);
					return exprType != null && Std.isOfType(expr, exprType) ? expr : null;
				 */
				// return null;
				return expr;
		}
	}

	function checkIsType(e1, e2):Bool {
		var expr1:Dynamic = expr(e1);

		return switch (Tools.expr(e2)) {
			case EIdent("Class"):
				Std.isOfType(expr1, Class);
			case EIdent("Map" | "IMap"):
				Std.isOfType(expr1, IMap);
			default:
				var expr2:Dynamic = expr(e2);
				expr2 != null ? Std.isOfType(expr1, expr2) : false;
		}
	}

	public inline function getCurOrigin():String
	{
		return #if hscriptPos
			curExpr.origin;
		#else
			"hscript";
		#end
	}
	public inline function getStaticVariableName(name:String):String
	{
		return getCurOrigin() + ":" + name;
	}

	public function varExists(name:String):Bool {
		return allowStaticVariables && staticVariables.exists(getStaticVariableName(name)) || allowPublicVariables && publicVariables.exists(name) || variables.exists(name);
	}

	public function findScriptClassDescriptor(name:String) {
		return _scriptClassDescriptors.get(name);
	}

	public function setVar(name:String, v:Dynamic) {
		if (_proxy != null) {
			if (_proxy.superHasField(name)) {
				UnsafeReflect.setProperty(_proxy.superClass, name, v);
			} else if (_proxy.superHasField('set_$name')) {
				UnsafeReflect.field(_proxy.superClass, 'set_$name')(v);
			}
		}
		if (allowStaticVariables && staticVariables.exists(__staticId = getStaticVariableName(name)))
			staticVariables.set(__staticId, v);
		else if (allowPublicVariables && publicVariables.exists(name))
			publicVariables.set(name, v);
		else
			variables.set(name, v);
	}

	// ENUM!!!!
	public function importEnum(enm:Enum<Dynamic>, ?asName:String) {
		if (enm == null)
			return;
		var enumThingy = {};
		for (c in enm.getConstructors()) {
			try {
				UnsafeReflect.setField(enumThingy, c, enm.createByName(c));
			} catch (e) {
				try {
					UnsafeReflect.setField(enumThingy, c, UnsafeReflect.field(enm, c));
				} catch (ex) {
					throw e;
				}
			}
		}
		if (asName == null) {
			var splitName = Type.getEnumName(enm).split(".");
			variables.set(splitName[splitName.length - 1], enumThingy);
		} else {
			variables.set(asName, enumThingy);
		}

		for (i in UnsafeReflect.fields(enumThingy)) {
			variables.set(i, UnsafeReflect.field(enumThingy, i));
		}
	}

	function assign(e1:Expr, e2:Expr):Dynamic {
		var v = expr(e2);
		// if (_proxy != null)
		// {
		// 	trace(id);
		// 	trace(v);
		// }
		switch (Tools.expr(e1)) {
			case EIdent(id):
				if (!locals.exists(id)) {
					if (_hasScriptObject && !varExists(id)) {
						var instanceHasField = __instanceFields.contains(id);

						if (_scriptObjectType == SObject && instanceHasField) {
							UnsafeReflect.setField(scriptObject, id, v);
							return v;
						}
						/*
							else if (_scriptObjectType == SCustomClass && instanceHasField) {
								var obj = cast(scriptObject, IHScriptCustomClassBehaviour);
								if(isBypassAccessor) {
									obj.__allowSetGet = false;
									var res = obj.hset(id, v);
									obj.__allowSetGet = true;
									return res;
								}
								return obj.hset(id, v);
							}
						 */
						else if (_scriptObjectType == SBehaviourClass) {
							var obj = cast(scriptObject, IHScriptCustomBehaviour);
							return obj.hset(id, v);
						}

						if (instanceHasField) {
							if (isBypassAccessor) {
								UnsafeReflect.setField(scriptObject, id, v);
								return v;
							} else {
								UnsafeReflect.setProperty(scriptObject, id, v);
								return UnsafeReflect.field(scriptObject, id);
							}
						} else if (__instanceFields.contains('set_$id')) { // setter
							return UnsafeReflect.getProperty(scriptObject, 'set_$id')(v);
						} else {
							setVar(id, v);
						}
					} else {
						setVar(id, v);
					}
				} else {
					var l = locals.get(id);
					l.r = v;
					if (l.depth == 0) {
						setVar(id, v);
					}
				}
			// TODO
			case EField(e, f, s):
				// if (Tools.expr(e).match(EIdent("this")) && _proxy != null && _proxy.superClass !=null && _proxy.superHasField(f))
				// {
				// 	UnsafeReflect.setProperty(_proxy.superClass, f, v);
				// 	return v;
				// }
				// TODO: Fix bug with assign after "trace(this)" and not
				var obj = expr(e);
				if (s && obj == null)
					return null;
				v = set(obj, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					setMapValue(arr, index, v);
				} else {
					arr[index] = v;
				}

			default:
				error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp(op, fop:Dynamic->Dynamic->Dynamic) {
		var me = this;
		binops.set(op, function(e1, e2) return me.evalAssignOp(op, fop, e1, e2));
	}

	function evalAssignOp(op, fop, e1, e2):Dynamic {
		var v;
		switch (Tools.expr(e1)) {
			case EIdent(id):
				v = fop(expr(e1), expr(e2));
				if (!locals.exists(id)) {
					if (_hasScriptObject && !varExists(id)) {
						var instanceHasField = __instanceFields.contains(id);

						if (_scriptObjectType == SObject && instanceHasField) {
							UnsafeReflect.setField(scriptObject, id, v);
							return v;
						}
						/*
							else if (_scriptObjectType == SCustomClass && instanceHasField) {
								var obj = cast(scriptObject, IHScriptCustomClassBehaviour);
								if(isBypassAccessor) {
									obj.__allowSetGet = false;
									var res = obj.hset(id, v);
									obj.__allowSetGet = true;
									return res;
								}
								return obj.hset(id, v);
							}
						 */
						else if (_scriptObjectType == SBehaviourClass) {
							var obj = cast(scriptObject, IHScriptCustomBehaviour);
							return obj.hset(id, v);
						}

						if (instanceHasField) {
							if (isBypassAccessor) {
								UnsafeReflect.setField(scriptObject, id, v);
								return v;
							} else {
								UnsafeReflect.setProperty(scriptObject, id, v);
								return UnsafeReflect.field(scriptObject, id);
							}
						} else if (__instanceFields.contains('set_$id')) { // setter
							return UnsafeReflect.getProperty(scriptObject, 'set_$id')(v);
						} else {
							setVar(id, v);
						}
					} else {
						setVar(id, v);
					}
				} else {
					var l = locals.get(id);
					l.r = v;
					if (l.depth == 0) {
						setVar(id, v);
					}
				}
			case EField(e, f, s):
				var obj = expr(e);
				if (s && obj == null)
					return null;
				v = fop(get(obj, f), expr(e2));
				v = set(obj, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					var map = getMap(arr);

					v = fop(map.get(index), expr(e2));
					map.set(index, v);
				} else {
					v = fop(arr[index], expr(e2));
					arr[index] = v;
				}
			default:
				return error(EInvalidOp(op));
		}
		return v;
	}

	function increment(e:Expr, prefix:Bool, delta:Int):Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EIdent(id):
				if (locals.exists(id)) {
					var l = locals.get(id);
					var v:Dynamic = l.r;
					if (prefix) {
						v += delta;
						l.r = v;
					} else
						l.r = v + delta;
					return v;
				} else {
					var v:Dynamic = resolve(id);
					if (prefix) {
						v += delta;
						setVar(id, v);
					} else
						setVar(id, v + delta);
					return v;
				}
			case EField(e, f, s):
				var obj = expr(e);
				if (s && obj == null)
					return null;
				var v:Dynamic = get(obj, f);
				if (prefix) {
					v += delta;
					set(obj, f, v);
				} else
					set(obj, f, v + delta);
				return v;
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					var map = getMap(arr);

					var v = map.get(index);
					if (prefix) {
						v += delta;
						map.set(index, v);
					} else {
						map.set(index, v + delta);
					}
					return v;
				} else {
					var v = arr[index];
					if (prefix) {
						v += delta;
						arr[index] = v;
					} else
						arr[index] = v + delta;
					return v;
				}
			default:
				return error(EInvalidOp((delta > 0) ? "++" : "--"));
		}
	}

	public function execute(expr:Expr):Dynamic {
		depth = 0;
		locals = new HXStringMap();
		declared = new Array();
		return exprReturn(expr);
	}

	function exprReturn(e):Dynamic {
		try {
			try {
				return expr(e);
			} catch (e:Stop) {
				switch (e) {
					case SBreak:
						throw "Invalid break";
					case SContinue:
						throw "Invalid continue";
					case SReturn:
						var v = returnValue;
						returnValue = null;
						return v;
				}
			} catch (e) {
				error(ECustom('${e.toString()}'));
				return null;
			}
		} catch (e:Error) {
			if (errorHandler != null)
				errorHandler(e);
			else
				throw e;
			return null;
		} catch (e) {
			trace(e);
		}
		return null;
	}

	public function duplicate<T>(h:HXStringMap<T>) {
		var h2 = new HXStringMap<T>();
		for (k in h.keys())
			h2.set(k, h.get(k));
		return h2;
	}

	function restore(old:Int) {
		while (declared.length > old) {
			var d = declared.pop();
			locals.set(d.n, d.old);
		}
	}

	public inline function error(e:#if hscriptPos ErrorDef #else Error #end, rethrow = false):Dynamic {
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end

		if (rethrow) {
			this.rethrow(e);
		} else {
			throw e;
		}
		return null;
	}

	inline function rethrow(e:Dynamic) {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	public function resolve(id:String, doException:Bool = true, resolveClass:Bool = true):Dynamic {
		// trace(id);
		if (id == null || id == "null")
			return null;
		id = StringTools.trim(id);
		if (id == "super" && _proxy != null) {
			_proxy._nextFromSuper = _proxy.superClass != null;
			return _proxy._nextFromSuper ? _proxy.superClass : _proxy.superConstructor;
		}

		if (variables.exists(id))
			return variables.get(id);
		if (publicVariables.exists(id))
			return publicVariables.get(id);
		if (staticVariables.exists(__staticId = getStaticVariableName(id)))
			return staticVariables.get(__staticId);
		// if (customClasses.exists(id))
		// 	return customClasses.get(id);

		if (_hasScriptObject) {
			// search in object
			if (id == "this") {
				return _proxy != null ? _proxy.superClass : scriptObject;
			}
			var instanceHasField = __instanceFields.contains(id);

			switch (_scriptObjectType) {
				case SObject:
					if (instanceHasField)
						return UnsafeReflect.field(scriptObject, id);
				// case SCustomClass:
				case SBehaviourClass:
					if (instanceHasField)
						return cast(scriptObject, IHScriptCustomBehaviour).hget(id);
				default:
					if (instanceHasField) {
						if (isBypassAccessor) {
							return UnsafeReflect.field(scriptObject, id);
						} else {
							return UnsafeReflect.getProperty(scriptObject, id);
						}
					} else if (__instanceFields.contains('get_$id')) { // getter
						return UnsafeReflect.getProperty(scriptObject, 'get_$id')();
					}
			}
		}
		if (resolveClass && _proxy == null) {
			#if !macro
			if (ClassTools.typedefDefines.exists(id))
				id = ClassTools.typedefDefines.get(id);
			#end
			var cl:Class<Dynamic> = Type.resolveClass(id); // now you can do this thing: var a:haxe.io.Path = new haxe.io.Path();  yee
			if (cl == null)
				cl = Type.resolveClass('${id}_HSC');
			/*
			if (cl == null)
			{
				var lastDot = id.lastIndexOf(".");
				if (lastDot != -1) // try get static variable
				{
					var idPost = id.substring(0, lastDot);
					cl = Type.resolveClass(idPost);
					if (cl == null)
						cl = Type.resolveClass('${idPost}_HSC');
					if (cl != null)
					{
						variables.set(id, cl);
						return cl;
					}
				}
			}
			else
			*/
			if (cl != null) {
				variables.set(id, cl);
				return cl;
			}
		}

		if (parentInterp != null) {
			var expr = parentInterp.resolve(id, false, false);
			if (expr != null)
				return expr;
		}
		if (doException)
			error(EUnknownVariable(id));
		return null;
	}

	public function expr(e:Expr):Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EClass(name, _):
				if (customClasses.exists(name))
					error(EAlreadyExistingClass(name));

				/*
					function importVar(thing:String):String {
						if (thing == null)
							return null;
						final variable:Class<Dynamic> = customClasses.exists(thing) ? null : resolve(thing, false);
						return variable == null ? thing : Type.getClassName(variable);
					}
					customClasses.set(name, new PolymodScriptClass(this, name, fields, importVar(extend), [for (i in interfaces) importVar(i)]));
				 */
				customClasses.set(name, e);
			case EUsing(pkg):
				if (!usingEnabled)
					return null;
				trace(pkg);
				var cl = Type.resolveClass(pkg);
				// if (cl == null)
				// 	cl = Type.resolveClass('${realClassName}_HSC');

				if (cl == null)
				// if (importFailedCallback == null || !importFailedCallback(pkg.split(".")))
					error(EInvalidClass(pkg.substr(pkg.lastIndexOf(".") + 1)));
				usingClasses.add(cl);
				return null;
			case EImportStar(pkg):
				#if !macro
				if (!importEnabled)
					return null;
				// trace(pkg);

				// var p = pkg.split(".");
				// if (p.length > 1)
				// 	p[p.length - 1] = "_" + p[p.length - 1];
				// var altPkg = p.join(".");
				// trace(altPkg);

				/*
					var c = Type.resolveClass(pkg);
					// if (c == null) Type.resolveClass(pkg + "_HSC");
					if (c == null) c = Type.resolveClass(altPkg);
					if (c == null) Type.resolveClass(altPkg + "_HSC");
				 */
				/*
					if( c != null )
					{
						var fields = UnsafeReflect.fields(c);
						trace(UnsafeReflect.fields(c));
						trace(Type.getClassFields(c));
						for( field in fields )
						{
							var f = UnsafeReflect.getProperty(c,field);
							if(f != null)
								variables.set(field,f);
						}
					}
					else
				 */
				{
					var importList:Array<String> = [];
					for (i in ClassTools.allClassesAvailable) {
						// if(i.length < pkg.length)
						// 	continue;
						if (!(StringTools.startsWith(i, pkg)
							&& i.substr(pkg.length + 1)
								.indexOf(".") == -1) // && !(StringTools.startsWith(i, altPkg) && i.substr(altPkg.length + 1).indexOf(".") == -1)
						)
							continue;
						importList.push(i);
					}
					for (i in importList)
						if (StringTools.endsWith(i, "_HSC") && importList.contains(i.substr(0, i.length - 4)))
							importList.remove(i); // remove duplicate
					// trace(importList);
					for (i in importList)
						expr(#if hscriptPos {
							e: EImport(i),
							pmin: curExpr.pmin,
							pmax: curExpr.pmax,
							origin: curExpr.origin,
							line: curExpr.line,
						} #else EImport(i) #end);
				}
				#end
				return null;

			case EImport(c, n):
				if (!importEnabled)
					return null;
				var splitClassName = [for (e in c.split(".")) e.trim()];
				var realClassName = splitClassName.join(".");
				#if !macro
				if (ClassTools.typedefDefines.exists(realClassName))
					realClassName = ClassTools.typedefDefines.get(realClassName);
				#end
				var claVarName = splitClassName[splitClassName.length - 1];
				var toSetName = n != null ? n : claVarName;
				var oldClassName = realClassName;
				var oldSplitName = splitClassName.copy();

				if (variables.exists(toSetName)) // class is already imported
					return null;

				if (importBlocklist.contains(realClassName))
					return null;
				var cl = Type.resolveClass(realClassName);
				if (cl == null)
					cl = Type.resolveClass('${realClassName}_HSC');

				var en = Type.resolveEnum(realClassName);

				// trace(realClassName, cl, en, splitClassName);

				// Allow for flixel.ui.FlxBar.FlxBarFillDirection;
				if (cl == null && en == null) {
					if (splitClassName.length > 1) {
						splitClassName.splice(-2, 1); // Remove the last last item
						realClassName = splitClassName.join(".");

						#if !macro
						if (ClassTools.typedefDefines.exists(realClassName))
							realClassName = ClassTools.typedefDefines.get(realClassName);
						#end

						if (importBlocklist.contains(realClassName))
							return null;

						cl = Type.resolveClass(realClassName);
						if (cl == null)
							cl = Type.resolveClass('${realClassName}_HSC');

						en = Type.resolveEnum(realClassName);

						// trace(realClassName, cl, en, splitClassName);
					}
				}

				if (cl == null && en == null) {
					if (importFailedCallback == null || !importFailedCallback(oldSplitName))
						error(EInvalidClass(oldClassName));
				} else {
					if (en != null) {
						importEnum(en, toSetName);
					} else {
						variables.set(toSetName, cl);
					}
				}

				return null;

			case EConst(c):
				switch (c) {
					case CInt(v): return v;
					case CFloat(f): return f;
					case CString(s): return s;
					#if !haxe3
					case CInt32(v): return v;
					#end
				}
			case EIdent(id):
				var l = locals.get(id);
				if (l != null)
					return l.r;
				return resolve(id);
			case EVar(n, type, e, isPublic, isStatic):
				var initExpr:Dynamic = null;
				if (e != null) {
					initExpr = castExprByType(expr(e), type);
				}
				declared.push({n: n, old: locals.get(n), depth: depth});
				locals.set(n, {r: initExpr, depth: depth});
				if (depth == 0) {
					if (isStatic == true && allowStaticVariables) {
						n = getStaticVariableName(n);
						if (!staticVariables.exists(n)) {
							staticVariables.set(n, initExpr);
						}
						return null;
					}
					(isPublic && allowPublicVariables ? publicVariables : variables).set(n, initExpr);
				}
				return null;
			case EBlock(exprs):
				var old = declared.length;
				var v = null;
				for (e in exprs)
					v = expr(e);
				restore(old);
				return v;
			case EField(e, f, s):
				var field = expr(e);
				if (s && field == null)
					return null;
				return get(field, f);
			case EBinop(op, e1, e2):
				var fop = binops.get(op);
				if (fop == null)
					error(EInvalidOp(op));
				return fop(e1, e2);
			case EUnop(op, prefix, e):
				switch (op) {
					case "!":
						return expr(e) != true;
					case "-":
						return -expr(e);
					case "++":
						return increment(e, prefix, 1);
					case "--":
						return increment(e, prefix, -1);
					case "~":
						#if (neko && !haxe3)
						return haxe.Int32.complement(expr(e));
						#else
						return ~expr(e);
						#end
					default:
						error(EInvalidOp(op));
				}
			case ECall(e, params):
				var args = [for (p in params) expr(p)];

				switch (Tools.expr(e)) {
					case EField(e, f, s):
						var obj = expr(e);
						if (obj == null) {
							if (s)
								return null;
							error(EInvalidAccess(f));
						}
						return fcall(obj, f, args);
					default:
						return call(null, expr(e), args);
				}
			case EIf(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else if (e2 == null) null else expr(e2);
			case EWhile(econd, e):
				whileLoop(econd, e);
				return null;
			case EDoWhile(econd, e):
				doWhileLoop(econd, e);
				return null;
			case EFor(v, it, e, ithv):
				forLoop(v, it, e, ithv);
				return null;
			case EBreak:
				throw SBreak;
			case EContinue:
				throw SContinue;
			case EReturn(e):
				returnValue = e == null ? null : expr(e);
				throw SReturn;
			case EFunction(params, fexpr, name, type, isPublic, isStatic, isOverride):
				var capturedLocals:Map<String, DeclaredVar> = [for (k => e in locals)
					if (e != null && e.depth > 0)
						k => e
				];

				var me:Interp = this;
				var hasOpt:Bool = false;
				var minParams:Int = 0;
				for (p in params) {
					if (p.opt) {
						hasOpt = true;
					} else {
						minParams++;
					}
				}
				var f = UnsafeReflect.makeVarArgs(function(args:Array<Dynamic>) {
					if (me.locals == null || me.variables == null)
						return null;

					if (((args == null) ? 0 : args.length) != params.length) {
						if (args.length < minParams) {
							var str:String = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
							if (name != null)
								str += " for function '" + name + "'";
							error(ECustom(str));
						}
						// make sure mandatory args are forced
						var args2 = [];
						var extraParams:Int = args.length - minParams;
						var pos:Int = 0;
						for (p in params) {
							if (p.opt) {
								if (extraParams > 0) {
									args2.push(castExprByType(args[pos++], p.t));
									extraParams--;
								} else {
									args2.push(null);
								}
							} else {
								args2.push(castExprByType(args[pos++], p.t));
							}
						}
						args = args2;
					}
					var old = me.locals, depth = me.depth;
					me.depth++;
					me.locals = me.duplicate(capturedLocals);
					for (i in 0...params.length)
						me.locals.set(params[i].name, {r: args[i], depth: depth});
					var r:Null<Dynamic> = null;
					var oldDecl:Int = declared.length;
					if (inTry)
						try {
							r = castExprByType(me.exprReturn(fexpr), type);
						} catch (e:Dynamic) {
							restore(oldDecl);
							me.locals = old;
							me.depth = depth;
							#if neko
							neko.Lib.rethrow(e);
							#else
							throw e;
							#end
						}
					else
						r = castExprByType(me.exprReturn(fexpr), type);
					restore(oldDecl);
					me.locals = old;
					me.depth = depth;
					return r;
				});
				if (name != null) {
					if (depth == 0) {
						// global function
						if (isStatic && allowStaticVariables)
						{
							staticVariables.set(getStaticVariableName(name), f);
						}
						else
						{
							((isPublic && allowPublicVariables) ? publicVariables : variables).set(name, f);
						}
					} else {
						// function-in-function is a local function
						declared.push({n: name, old: locals.get(name), depth: depth});
						var ref:DeclaredVar = {r: f, depth: depth};
						locals.set(name, ref);
						capturedLocals.set(name, ref); // allow self-recursion
					}
				}
				return f;
			case EArrayDecl(arr, wantedType):
				var isMap = false;
				if (wantedType != null) {
					isMap = wantedType.match(CTPath(["Map"], [_, _]));
				} else {
					isMap = arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _));
				}
				if (isMap) {
					var keys = [];
					var values = [];
					for (e in arr) {
						switch (Tools.expr(e)) {
							case EBinop("=>", eKey, eValue):
								keys.push(expr(eKey));
								values.push(expr(eValue));
							default: throw("=> expected");
						}
					}
					return makeMap(keys, values, wantedType);
				} else {
					return [for (i in arr) expr(i)];
				}
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					return getMapValue(arr, index);
				} else {
					return arr[index];
				}
			case ENew(cl, params):
				return cnew(cl, [for (e in params) expr(e)]);
			case EThrow(e):
				throw expr(e);
			case ETry(e, n, _, ecatch):
				var old = declared.length;
				var oldTry = inTry;
				try {
					inTry = true;
					var v:Dynamic = expr(e);
					restore(old);
					inTry = oldTry;
					return v;
				} catch (err:Stop) {
					inTry = oldTry;
					throw err;
				} catch (err:Dynamic) {
					// restore vars
					restore(old);
					inTry = oldTry;
					// declare 'v'
					declared.push({n: n, old: locals.get(n), depth: depth});
					locals.set(n, {r: err, depth: depth});
					var v:Dynamic = expr(ecatch);
					restore(old);
					return v;
				}
			case EObject(fl):
				var o:Dynamic = {};
				for (f in fl)
					UnsafeReflect.setField(o, f.name, expr(f.e));
				return o;
			case ETernary(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else expr(e2);
			case ESwitch(e, cases, def):
				var val:Dynamic = expr(e);
				var match = false;
				for (c in cases) {
					for (v in c.values)
						if (expr(v) == val) {
							match = true;
							break;
						}
					if (match) {
						val = expr(c.expr);
						break;
					}
				}
				if (!match)
					val = def == null ? null : expr(def);
				return val;
			case EMeta(name, args, e):
				if (onMetadata != null) {
					return onMetadata(name, args, e);
				}
				var oldAccessor = isBypassAccessor;
				if (name == ":bypassAccessor") {
					isBypassAccessor = true;
				}
				var val = expr(e);

				isBypassAccessor = oldAccessor;
				return val;
			case ECheckType(e, type):
				return castExprByType(expr(e), type);
			case EParent(e):
				return expr(e);
		}
		return null;
	}

	function makeMap(keys:Array<Dynamic>, values:Array<Dynamic>, ?wantedType:Null<CType>):Dynamic {
		var isAllString:Bool = false;
		var isAllInt:Bool = false;
		var isAllObject:Bool = false;
		var isAllEnum:Bool = false;
		switch (wantedType) {
			case CTPath(["Map"], [CTPath(path, _), _]):
				switch (path) {
					case ["String"]:
						isAllString = true;
					case ["Int"]:
						isAllInt = true;
					case _:
				}
			case _:
		}
		if (isAllString || isAllInt) {
			isAllObject = false;
			isAllEnum = false;
		} else {
			isAllString = true;
			isAllInt = true;
			isAllObject = true;
			isAllEnum = true;
			for (key in keys) {
				isAllString = isAllString && (key is String);
				isAllInt = isAllInt && (key is Int);
				isAllObject = isAllObject && Reflect.isObject(key);
				isAllEnum = isAllEnum && Reflect.isEnumValue(key);
			}
			if (!isAllObject && !isAllEnum) {
				error(ECustom("Unknown Type Key"));
			}
		}

		if (isAllInt) {
			var m = new haxe.ds.IntMap<Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllString) {
			var m = new haxe.ds.StringMap<Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllEnum) {
			var m = new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllObject) {
			var m = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		error(ECustom("Invalid map keys " + keys));
		return null;
	}

	function doWhileLoop(econd, e) {
		var old = declared.length;
		do {
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		} while (expr(econd) == true);
		restore(old);
	}

	private function registerScriptClass(c:ClassDeclEx) {
		var name = c.name;
		if (c.pkg != null) {
			name = c.pkg.join(".") + "." + name;
		}
		_scriptClassDescriptors.set(name, c);
	}

	private var _scriptClassDescriptors:HXStringMap<ClassDeclEx> = new HXStringMap<ClassDeclEx>();

	function whileLoop(econd, e) {
		var old = declared.length;
		while (expr(econd) == true) {
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		}
		restore(old);
	}

	function makeIterator(v:Dynamic, ?allowKeyValue = false):Iterator<Dynamic> {
		#if ((flash && !flash9) || (php && !php7 && haxe_ver < '4.0.0'))
		if (v.iterator != null)
			v = v.iterator();
		#else
		if (allowKeyValue) {
			try
				v = v.keyValueIterator()
			catch (e:Dynamic) {};
		}

		if (v.hasNext == null || v.next == null) {
			try
				v = v.iterator()
			catch (e:Dynamic) {};
		}
		#end
		if (v.hasNext == null || v.next == null)
			error(EInvalidIterator(v));
		return v;
	}

	function forLoop(n, it, e, ?ithv) {
		var isKeyValue = ithv != null;
		var old = declared.length;
		if (isKeyValue)
			declared.push({n: ithv, old: locals.get(ithv), depth: depth});
		declared.push({n: n, old: locals.get(n), depth: depth});
		var it = makeIterator(expr(it), isKeyValue);
		var _hasNext = it.hasNext;
		var _next = it.next;
		var next;
		while (_hasNext()) {
			next = _next();
			if (isKeyValue)
				locals.set(ithv, {r: next.key, depth: depth});
			locals.set(n, {r: isKeyValue ? next.value : next, depth: depth});
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		}
		restore(old);
	}

	inline function getMap(map:Dynamic):IMap<Dynamic, Dynamic> {
		return cast(map, IMap<Dynamic, Dynamic>);
	}

	inline function isMap(o:Dynamic):Bool {
		return (o is IMap);
	}

	inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
		return cast(map, IMap<Dynamic, Dynamic>).get(key);
	}

	inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
		cast(map, IMap<Dynamic, Dynamic>).set(key, value);
	}

	public static var getRedirects:HXStringMap<(Dynamic, String) -> Dynamic> = [];
	public static var setRedirects:HXStringMap<(Dynamic, String, Dynamic) -> Dynamic> = [];

	private static var _getRedirect:Dynamic->String->Dynamic;
	private static var _setRedirect:Dynamic->String->Dynamic->Dynamic;

	public var useRedirects:Bool = false;

	static function getClassType(o:Dynamic, ?cls:Class<Any>):Null<String> {
		return switch Type.typeof(o) {
			case TNull: "Null";
			case TInt: "Int";
			case TFloat: "Float";
			case TBool: "Bool";
			case _:
				if (cls == null)
					cls = Type.getClass(o);
				cls != null ? Type.getClassName(cls) : null;
		}
	}

	function get(o:Dynamic, f:String):Dynamic {
		if (o == null)
			error(EInvalidAccess(f));
		var cls = Type.getClass(o);
		if (useRedirects && {
			var cl:Null<String> = getClassType(o, cls);
			cl != null && (_getRedirect = getRedirects[cl]) != null;
		}) {
			return _getRedirect(o, f);
		}
		var v = null;
		if (Std.isOfType(o, PolymodScriptClass)) {
			// trace(f);
			// var proxy:PolymodAbstractScriptClass = cast(o, PolymodScriptClass);
			// if (proxy._interp.variables.exists(f))
			// {
			// 	return proxy._interp.variables.get(f);
			// }
			// else if (proxy.superClass != null && proxy.superHasField(f))
			// {
			// 	return Reflect.getProperty(proxy.superClass, f);
			// }
			// else
			// {
			return cast(o, PolymodAbstractScriptClass).get(f);
			// }
		}
		if (Std.isOfType(o, HScriptedClass)) {
			var proxy:PolymodAbstractScriptClass = UnsafeReflect.field(o, "_asc");
			if (proxy != null)
				return proxy.get(f);
		}
		// if (o is HScriptedClass && o != scriptObject) {
		// 	var proxy:PolymodAbstractScriptClass = Reflect.field(o, "_asc");
		// 	if (proxy._interp.variables.exists(f))
		// 	{
		// 		return proxy._interp.variables.get(f);
		// 	}
		// 	else if (proxy.superClass != null && proxy.superHasField(f))
		// 	{
		// 		return Reflect.getProperty(proxy.superClass, f);
		// 	}
		// }
		if (isBypassAccessor && (v = Reflect.field(o, f)) == null) {
			v = Reflect.field(cls, f);
		}
		if (v == null && (v = Reflect.getProperty(o, f)) == null) {
			v = Reflect.getProperty(cls, f);
		}

		return v;
	}

	function set(o:Dynamic, f:String, v:Dynamic):Dynamic {
		if (o == null)
			error(EInvalidAccess(f));

		if (useRedirects && {
			var cl:Null<String> = getClassType(o);
			cl != null && (_setRedirect = setRedirects[cl]) != null;
		})
			return _setRedirect(o, f, v);
		// if (o is HScriptedClass)
		// {
		// 	var proxy:PolymodScriptClass = Reflect.field(o, "_asc");
		// 	if (proxy._interp.variables.exists(f))
		// 	{
		// 		proxy._interp.variables.set(f, v);
		// 	}
		// 	else if (proxy.superClass != null && UnsafeReflect.hasField(proxy.superClass, f))
		// 	{
		// 		UnsafeReflect.setProperty(proxy.superClass, f, v);
		// 	}
		// 	else if (proxy.superClass != null && UnsafeReflect.hasField(_proxy.superClass, f))
		// 	{
		// 		UnsafeReflect.setProperty(proxy.superClass, f, v);
		// 	}
		// 	return v;
		// }
		if (Std.isOfType(o, PolymodScriptClass)) {
			/*
				var proxy:PolymodScriptClass = cast(o, PolymodScriptClass);
				if (proxy._interp.variables.exists(f))
				{
					proxy._interp.variables.set(f, v);
				}
				else if (proxy.superClass != null && UnsafeReflect.hasField(proxy.superClass, f))
				{
					UnsafeReflect.setProperty(proxy.superClass, f, v);
				}
				return v;
			 */
			return cast(o, PolymodAbstractScriptClass).set(f, v);
		}
		if (Std.isOfType(o, HScriptedClass)) {
			var proxy:PolymodAbstractScriptClass = UnsafeReflect.field(o, "_asc");
			if (proxy != null)
				return proxy.set(f, v);
			// return cast(UnsafeReflect.field(o, "_asc"), PolymodAbstractScriptClass).set(f, v);
		}
		if (isBypassAccessor)
			UnsafeReflect.setField(o, f, v);
		else
			UnsafeReflect.setProperty(o, f, v);
		return v;
	}

	function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
		// OVERRIDE CHANGE: Custom logic to handle super calls to prevent infinite recursion
		/*
			if (o == scriptObject && _scriptObjectType == SCustomClass)
			{
				// Force call super function.
				var func:Function;
				if ((func = variables.get(f)) == null && (func = publicVariables.get(f)) == null)
					func = get(scriptObject, "__hsx_super_" + f);
				return func == null ? null : call(scriptObject, func, args);
			}
		 */
		/*
			if (_proxy != null && o == _proxy.superClass && f.indexOf("__hsx_super_") != 0)
			{
				// Force call super function.
				return this.fcall(o, '__hsx_super_${f}', args);
			}
			else
		 */
		if (Std.isOfType(o, PolymodScriptClass)) {
			// _nextCallObject = null;
			return cast(o, PolymodScriptClass).callFunction(f, args);
		} else if (Std.isOfType(o, HScriptedClass)) {
			return UnsafeReflect.field(o, "_asc").callFunction(f, args);
		}

		var func:Function = get(o, f);

		if (func == null) {
			for (i in usingClasses)
			{
				func = Reflect.field(i, f); // todo?: ignore @:noUsing
				if (func != null)
				{
					args.insert(0, o);
					break;
				}
			}
		}
		// #if html
		// Workaround for an HTML5-specific issue.
		// https://github.com/HaxeFoundation/haxe/issues/11298
		if (func == null && f == "contains") {
			func = get(o, "includes");
		}
		// #end

		// if(func == null && o == scriptObject && _scriptObjectType == SCustomClass) {
		// 	return UnsafeReflect.callMethod(scriptObject, UnsafeReflect.field(scriptObject, "__hsx_super_" + f), args);
		// }
		return func == null ? null : call(o, func, args);
	}

	function call(o:Dynamic, f:Function, args:Array<Dynamic>):Dynamic {
		// if(f == CustomClassHandler.staticHandler) {
		// 	return null;
		// }
		return UnsafeReflect.callMethod(o, f, args);
	}

	function callThis(fun:Function, args:Array<Dynamic>):Dynamic {
		// If we are calling this.fn(), special handling is needed to prevent the local scope from being destroyed.
		// Store the local scope.
		var capturedLocals = this.duplicate(locals);
		var capturedDeclared = this.declared;
		var capturedDepth = this.depth;

		this.depth++;

		// Call the function.
		var result = UnsafeReflect.callMethod(scriptObject, fun, args);

		this.depth--;

		// Restore the local scope.
		this.locals = capturedLocals;
		this.declared = capturedDeclared;
		this.depth = capturedDepth;

		return result;
	}

	function getCustomClass(clName:String):Null<Dynamic> {
		var cl = customClasses.get(clName);
		if (cl == null && parentInterp != null)
			return parentInterp.getCustomClass(clName);
		else
			return cl;
	}

	function cnew(cl:String, args:Array<Dynamic>):Dynamic {
		switch (getCustomClass(cl)) {
			case EClass(_, fields, extend, interfaces):
				// try
				// {
				var scriptedCls:Dynamic;
				if (extend == null)
					return UnsafeReflect.field(hscript.custom_classes.TemplateClass, "__hsx_init")(cl, this, args);

				final variable:Class<Dynamic> = customClasses.exists(extend) ? null : resolve(extend, false);
				if (UnsafeReflect.hasField(variable, "__hsx_init")) {
					trace(variable);
					return UnsafeReflect.field(variable, "__hsx_init")(cl, this, args);
				}
				scriptedCls = variable == null ? extend : Type.getClassName(variable);
				if (scriptedCls == null || (scriptedCls = Type.resolveClass(scriptedCls + "_HSX")) == null) {
					error(EInvalidClass(extend));
					return null;
				}
				return UnsafeReflect.field(scriptedCls, "__hsx_init")(cl, this, args);
			// }
			// catch(e)
			// {
			// 	trace("    " + e);
			// 	trace("    " + e.details());
			// 	return null;
			// }

			default:
				return Type.createInstance(resolve(cl), args);
		}
	}

	public function createScriptClassInstance(className:String, ?args:Array<Dynamic>):PolymodAbstractScriptClass {
		switch (getCustomClass(className)) {
			case EClass(className, fields, extend, interfaces):
				function importVar(thing:String):Class<Dynamic> {
					if (thing == null)
						return null;
					final variable:Class<Dynamic> = customClasses.exists(thing) ? null : resolve(thing); // TODO: Allow extend inner scripted class
					if (variable != null && UnsafeReflect.hasField(variable, "__hsx_init")) {
						trace(variable);
						return variable;
					}
					return variable == null ? null : Type.resolveClass('${Type.getClassName(variable)}_HSX');
				}
				return new PolymodScriptClass(this, className, fields, importVar(extend), [] /*[for (i in interfaces) importVar(i)]*/, args);
			default:
				return null;
		}
	}
}
