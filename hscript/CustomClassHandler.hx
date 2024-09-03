package hscript;

import hscript.Interp.DeclaredVar;
import hscript.UnsafeReflect;

using StringTools;
/*
class CustomClassHandler implements IHScriptCustomConstructor {
	public static var staticHandler = new StaticHandler();

	public var ogInterp:Interp;
	public var name:String;
	public var fields:Array<Expr>;
	public var extend:String;
	public var interfaces:Array<String>;

	public var cl:Class<Dynamic>;

	public function new(ogInterp:Interp, name:String, fields:Array<Expr>, ?extend:String, ?interfaces:Array<String>) {
		this.ogInterp = ogInterp;
		this.name = name;
		this.fields = fields;
		this.extend = extend;
		this.interfaces = interfaces;

		this.cl = extend == null ? TemplateClass : Type.resolveClass('${extend}_HSX');
		if(cl == null)
			ogInterp.error(EInvalidClass(extend));
	}

	public function hnew(args:Array<Dynamic>):Dynamic {
		var interp = new Interp();

		interp.errorHandler = ogInterp.errorHandler;

		var _class:IHScriptCustomClassBehaviour = Type.createInstance(cl, args);

		var __capturedLocals = ogInterp.duplicate(ogInterp.locals);
		var capturedLocals:Map<String, DeclaredVar> = [];
		for(k=>e in __capturedLocals)
			if (e != null && e.depth <= 0)
				capturedLocals.set(k, e);

		var disallowCopy = Type.getInstanceFields(cl);

		for (key => value in capturedLocals) {
			if(!disallowCopy.contains(key)) {
				interp.locals.set(key, {r: value, depth: -1});
			}
		}
		for (key => value in ogInterp.variables) {
			if(!disallowCopy.contains(key)) {
				interp.variables.set(key, value);
			}
		}
		var comparisonMap = new Map();
		for(key => value in interp.variables) {
			comparisonMap.set(key, value);
		}

		_class.__custom__variables = interp.variables;

		//trace(fields);

		for(expr in fields) {
			@:privateAccess
			interp.exprReturn(expr);
		}

		interp.variables.set("super", staticHandler);

		_class.__interp = interp;
		interp.scriptObject = _class;

		// get only variables that were not set before
		var classVariables = [for(key => value in interp.variables) if(!comparisonMap.exists(key) || comparisonMap[key] != value) key => value];
		for(variable => value in classVariables) {
			if(variable == "this" || variable == "super") continue;
			@:privateAccess
			if(!interp.__instanceFields.contains(variable)) {
				interp.__instanceFields.push(variable);
			}
		}

		var newFunc = interp.variables.get("new");
		if(newFunc != null) {
			UnsafeReflect.callMethod(null, newFunc, args);
		}

		//trace([for(key => value in classVariables) key]);
		//@:privateAccess
		//trace(interp.__instanceFields);

		_class.__allowSetGet = false;

		for(variable => value in interp.variables) {
			if(variable == "this") continue;
			if(variable.startsWith("set_") || variable.startsWith("get_")) {
				_class.__allowSetGet = true;
			}
		}

		var newFunc = interp.variables.get("new");
		if(newFunc != null) {
			UnsafeReflect.callMethodUnsafe(null, newFunc, args);
		}

		return _class;
	}

	public function toString():String {
		return name;
	}
}

class TemplateClass implements IHScriptCustomClassBehaviour implements IHScriptCustomBehaviour {
	public var __interp:Interp;
	public var __allowSetGet:Bool = true;
	public var __custom__variables:Map<String, Dynamic>;

	public function hset(name:String, val:Dynamic):Dynamic {
		if(__allowSetGet && __custom__variables.exists("set_" + name))
			return __callSetter(name, val);
		if (__custom__variables.exists(name)) {
			__custom__variables.set(name, val);
			return val;
		}
		UnsafeReflect.setProperty(this, name, val);
		return UnsafeReflect.field(this, name);
	}
	public function hget(name:String):Dynamic {
		if(__allowSetGet && __custom__variables.exists("get_" + name))
			return __callGetter(name);
		if (__custom__variables.exists(name))
			return __custom__variables.get(name);
		return UnsafeReflect.getProperty(this, name);
	}

	public function __callGetter(name:String):Dynamic {
		__allowSetGet = false;
		var v = __custom__variables.get("get_" + name)();
		__allowSetGet = true;
		return v;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		__allowSetGet = false;
		var v = __custom__variables.get("set_" + name)(val);
		__allowSetGet = true;
		return v;
	}
}

final class StaticHandler {
	public function new() {}
}
*/