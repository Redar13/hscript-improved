package hscript.custom_classes;

import haxe.CallStack;
import haxe.macro.Expr.Catch;
import hscript.custom_classes.PolymodClassDeclEx;
import hscript.Expr;
import hscript.Printer;
import hscript.Interp;
import hscript.UnsafeReflect;

using StringTools;

enum Param
{
	Unused;
}

/**
 * Grabbed from polymod (https://github.com/larsiusprime/polymod/tree/master/polymod/hscript)
 *
 * Provides handlers for scripted classes
 * Based on code by Ian Harrigan
 * @see https://github.com/ianharrigan/hscript-ex
 */
@:access(hscript.Interp)
@:allow(hscript.Interp)
class PolymodScriptClass
{
	/**
	 * Define a list of script classes to override the default behavior of Polymod.
	 * For example, script classes should import `ScriptedSprite` instead of `Sprite`.
	 */
	public static final scriptClassOverrides:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Provide a class name along with a corresponding class to override imports.
	 * You can set the value to `null` to prevent the class from being imported.
	 */
	public static final importOverrides:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Provide a class name along with a corresponding class to import it in every scripted class.
	 */
	public static final defaultImports:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	public static function createScriptClassInstance(clsName:String, interp:Interp, ?args:Array<Dynamic>):PolymodAbstractScriptClass
	{
		return interp.createScriptClassInstance(clsName, args);
	}

	public var name:String;
	public var extend:String;
	public var cl:Class<Dynamic>; // class referense
	public var fields:Array<Expr>;
	/**
	 * INSTANCE METHODS
	 */
	public function new(ogInterp:Interp, name:String, fields:Array<Expr>, ?extend:Class<Dynamic>, ?interfaces:Array<String>, ?args:Array<Dynamic>)
	{
		_parentInterp = ogInterp;
		superConstructor = Reflect.makeVarArgs(createSuperClass);
		this.name = name;
		this.fields = fields;
		this.cl = extend == null ? TemplateClass : extend;
		callNew(args);
	}
	/*
	public function new(c:ClassDeclEx, args:Array<Dynamic>, ?parentInterp:Interp)
	{
		var targetClass:Class<Dynamic> = null;
		switch (c.extend)
		{
			case CTPath(pth, params):
				var clsPath = pth.join('.');
				var clsName = pth[pth.length - 1];

				if (scriptClassOverrides.exists(clsPath)) {
					targetClass = scriptClassOverrides.get(clsPath);
				}
				else if (c.imports.exists(clsName))
				{
					var importedClass:ClassImport = c.imports.get(clsName);
					if (importedClass != null && importedClass.cls != null) {
						targetClass = importedClass.cls;
					}
				}
			default:
		}
		_interp = new Interp(targetClass);
		_interp._proxy = this;
		_c = c;
		_parentInterp = parentInterp;
	}
	*/

	public function callNew(?args:Array<Dynamic>)
	{
		_interp = new Interp(cl);
		_interp._proxy = this;
		// _c = c;
		if (_parentInterp != null)
		{
			_interp.errorHandler = _parentInterp.errorHandler;
			_interp.importFailedCallback = _parentInterp.importFailedCallback;
			_interp.onMetadata = _parentInterp.onMetadata;
			_interp.staticVariables = _parentInterp.staticVariables;
			#if hscriptPos
			_interp.variables.set("trace", UnsafeReflect.makeVarArgs(function(el) {
				var oldExpr = _parentInterp.curExpr;
				var curExpr = _interp.curExpr;
				_parentInterp.curExpr = curExpr;
				UnsafeReflect.callMethod(null, _parentInterp.variables.get("trace"), el);
				_parentInterp.curExpr = oldExpr;
			}));
			#end
		}

		if (fields != null)
		{
			for (i in fields)
				this._interp.expr(i);
			// fields = null;
		}

		if (findFunction("new") != null)
		{
			callFunction("new", args);
			/*
			if (superClass == null && _c.extend != null)
			{
				// _interp.errorEx(EClassSuperNotCalled);
			}
			*/
			if (_interp.scriptObject == null)
			{
				UnsafeReflect.setField(superClass, "_asc", this);
				_interp.scriptObject = superClass;
				__superClassFieldList = _interp.__instanceFields;
			}
		}
		else
		{
			createSuperClass(args);
		}
		// trace(superClass);
		// trace(Type.getClassName(Type.getClass(superClass)));
		return superClass;
	}

	var __superClassFieldList:Array<String> = null;

	public function superHasField(name:String):Bool
	{
		if (superClass == null)
			return false;
		// UnsafeReflect.hasField(this, name) is REALLY expensive so we use a cache.
		if (__superClassFieldList == null)
		{
			__superClassFieldList = Type.getInstanceFields(cl);
			// __superClassFieldList = Type.getInstanceFields(cl).filter(str -> return str.indexOf("__hsx_super_") != 0);
		}
		return __superClassFieldList.indexOf(name) != -1;
	}

	private function createSuperClass(args:Array<Dynamic>)
	{
		// if (args == null)
		// {
		// 	args = [];
		// }
		// var fullExtendString = '${extend}_HSX';

		// Build an unqualified path too.
		// var extendString = fullExtendString.substr(fullExtendString.lastIndexOf(".") + 1);

		// var classDescriptor = _interp.findScriptClassDescriptor(extendString);
		// if (classDescriptor != null)
		// {
		// 	superClass = new PolymodScriptClass(classDescriptor, args);
		// }
		// else
		{
			superClass = Type.createInstance(cl, args);
		}
		// trace(Type.getClass(superClass));
		// trace(Type.typeof(superClass));
		UnsafeReflect.setField(superClass, "_asc", this);
		_interp.scriptObject = superClass;
		__superClassFieldList = _interp.__instanceFields;
		return superClass;
	}

	var _nextIsSuper:Bool = false;
	@:privateAccess(hscript.Interp)
	public function callFunction(fnName:String, args:Array<Dynamic> = null):Dynamic
	{
		// trace(fnName); for (i in CallStack.callStack()) trace(Std.string(i));
		// Force call super function.
		var func:haxe.Constraints.Function = _nextIsSuper ? null : findFunction(fnName);
		if (func == null && superClass != null)
		{
			if (args != null)
				for (i => a in args)
				{
					if (Std.isOfType(a, PolymodScriptClass))
						args[i] = cast(a, PolymodScriptClass).superClass;
				}
			func = UnsafeReflect.field(superClass, "__hsx_super_" + fnName);
		}
		_nextIsSuper = false;
		// trace("call " + fnName);
		// trace(func != null);
		// return func == null ? null : _interp.callThis(func, args);
		return func == null ? null : _interp.call(null, func, args);
		/*
		var field = findField(fnName);
		var r:Dynamic = null;
		var fn = (field != null) ? findFunction(fnName, true) : null;

		if (fn != null)
		{
			var fn = findFunction(fnName);
			// previousValues is used to restore variables after they are shadowed in the local scope.
			var previousValues:Map<String, Dynamic> = [];
			var i = 0;
			for (a in fn.args)
			{
				var value:Dynamic = null;

				if (args != null && i < args.length)
				{
					value = args[i];
				}
				else if (a.value != null)
				{
					value = _interp.expr(a.value);
				}

				// NOTE: We assign these as variables rather than locals because those get wiped when we enter the function.
				if (_interp.variables.exists(a.name))
				{
					previousValues.set(a.name, _interp.variables.get(a.name));
				}
				_interp.variables.set(a.name, value);
				i++;
			}

			try
			{
				r = _interp.execute(fn.expr);
			}
			catch (err:Error)
			{
				// A script error occurred while executing the script function.
				// Purge the function from the cache so it is not called again.
				purgeFunction(fnName);
				return null;
			}

			for (a in fn.args)
			{
				if (previousValues.exists(a.name))
				{
					_interp.variables.set(a.name, previousValues.get(a.name));
				}
				else
				{
					_interp.variables.remove(a.name);
				}
			}
		}
		else
		{
			var fixedArgs = [];
			// OVERRIDE CHANGE: Use __super_ when calling superclass
			var fixedName = '__super_${fnName}';
			for (a in args)
			{
				if (Std.isOfType(a, PolymodScriptClass))
				{
					fixedArgs.push(cast(a, PolymodScriptClass).superClass);
				}
				else
				{
					fixedArgs.push(a);
				}
			}
			var fn = UnsafeReflect.field(superClass, fixedName);
			// if (fn == null)
			// {
			// 	Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
			// 		'Error while calling function super.${fnName}(): EInvalidAccess' + '\n' +
			// 		'InvalidAccess error: Super function "${fnName}" does not exist! Define it or call the correct superclass function.');
			// }
			r = UnsafeReflect.callMethod(superClass, fn, fixedArgs);
		}
		return r;
		*/
	}

	private var _c:ClassDeclEx;
	private var _interp:Interp;
	private var _parentInterp:Interp;

	public var superClass:Dynamic = null;

	public var className:String = "";
	/*
	public var className(get, null):String;

	private function get_className():String
	{
		var name = "";
		if (_c.pkg != null)
		{
			name += _c.pkg.join(".");
		}
		name += _c.name;
		return name;
	}
	*/
	var superConstructor:Dynamic = null;

	/*
	private function superConstructor(arg0:Dynamic = Unused, arg1:Dynamic = Unused, arg2:Dynamic = Unused, arg3:Dynamic = Unused)
	{
		var args = [];
		if (arg0 != Unused)
			args.push(arg0);
		if (arg1 != Unused)
			args.push(arg1);
		if (arg2 != Unused)
			args.push(arg2);
		if (arg3 != Unused)
			args.push(arg3);
		return createSuperClass(args);
	}
	*/

	/**
	 * Search for a function field with the given name.
	 * @param name The name of the function to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findFunction(name:String, cacheOnly:Bool = true):haxe.Constraints.Function
	{
		var func:haxe.Constraints.Function = _interp.variables.get(name);
		if (func == null)
			func = _interp.publicVariables.get(name);
		return func;
	}

	/**
	 * Remove a function from the cache.
	 * This is useful when a function is broken and needs to be skipped.
	 * @param name The name of the function to remove from the cache.
	 */
	private function purgeFunction(name:String):Void {
		if (_cachedFunctionDecls != null)
		{
			_cachedFunctionDecls.remove(name);
		}
	}

	public function get(name:String):Dynamic
	{
		name = StringTools.trim(name);
		switch name
		{
			case "superClass":			 return this.superClass;
			case "createSuperClass":	 return this.createSuperClass;
			case "findFunction":		 return this.findFunction;
			case "callFunction":		 return this.callFunction;
			case _:
				/*
				var varDecl:VarDecl = findVar(name);
				if (varDecl != null)
				{
					var varValue:Dynamic = null;
					if (_interp.variables.exists(name))
					{
						varValue = _interp.variables.get(name);
					}
					else
					{
						if (varDecl.expr != null)
						{
							_interp.variables.set(name, varValue = _interp.expr(varDecl.expr));
						}
					}
					return varValue;
				}
				*/

				/*
				var expr = _interp.publicVariables.get(name);
				if (expr == null && (expr = _interp.variables.get(name)) == null && superHasField(name))
					expr = UnsafeReflect.getProperty(superClass, name);
				return expr;
				*/

				var expr = findField(name);
				if (expr == null)
				{
					if (superClass != null && (expr = findSuperVar(name)) != null)
						return expr;
					/*
					if (_proxy.superHasField(id))
					{
						// _nextCallObject = _proxy.superClass;
						return UnsafeReflect.getProperty(_proxy.superClass, id);
					}
					*/
					// trace(id);
					if (_parentInterp != null)
					{
						return _parentInterp.resolve(name, false, false);
					}
				}
				return expr;

				/*
				if (_interp.varExists(name))
				{
					return _interp.resolve(name, true, false);
				}
				if (superClass != null) {
					if (cl == null) {
						// Anonymous structure
						if (Reflect.hasField(superClass, name)) {
							return Reflect.field(this.superClass, name);
						}
					} else if (Std.isOfType(this.superClass, PolymodScriptClass)) {
						try
						{
							return cast (this.superClass, PolymodScriptClass).get(name);
						}
						catch (e:Dynamic)
						{
						}
					} else {
						// Class object
						var fields = Type.getInstanceFields(cl);
						if (fields.contains(name) || fields.contains('get_$name')) {
							return Reflect.getProperty(this.superClass, name);
						} else {
							// throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class '"
							// 	+ Type.getClassName(Type.getClass(this.superClass)) + "'";
						}
					}
				}
				if (_parentInterp != null)
				{
					return _parentInterp.resolve(name, true, false);
				}
				*/
		}
		return null;
	}

	public function set(name:String, value:Dynamic):Dynamic
	{
		// switch (name)
		// {
		// 	case name:
				if (_interp.variables.exists(name))
				{
					_interp.variables.set(name, value);
					return value;
				}
				else if (_interp.publicVariables.exists(name))
				{
					_interp.publicVariables.set(name, value);
					return value;
				}
				return setSuperVar(name, value);
		// }
	}

	/**
	 * Search for a variable field with the given name.
	 * @param name The name of the variable to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findVar(name:String, cacheOnly:Bool = false):Dynamic
	{
		var v:Dynamic = _interp.variables.get(name);
		if (v == null)
			v = _interp.publicVariables.get(name);
		return v;
	}
	private function findSuperVar(name:String):Dynamic
	{
		if (superHasField(name)) {
			// if(_interp.isBypassAccessor) {
			// 	return UnsafeReflect.field(superClass, name);
			// } else {
				return UnsafeReflect.getProperty(superClass, name);
			// }
		} else if (superHasField('get_$name')) { // getter
			return UnsafeReflect.getProperty(superClass, 'get_$name')();
		}
		return null;
	}
	private function setSuperVar(name:String, value:Dynamic):Dynamic
	{
		if (superHasField(name))
		{
			UnsafeReflect.setProperty(superClass, name, value);
			return value;
		}
		else if (superHasField('set_$name'))
		{
			return UnsafeReflect.field(superClass, 'set_$name')(value);
		}
		return value;
	}

	/**
	 * Search for a field (function OR variable) with the given name.
	 * @param name The name of the field to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findField(name:String, cacheOnly:Bool = true):Dynamic
	{
		if (_interp.variables.exists(name))
			return _interp.variables.get(name);
		if (_interp.publicVariables.exists(name))
			return _interp.publicVariables.get(name);
		return null;
	}

	public function listFunctions():Map<String, FunctionDecl>
	{
		return _cachedFunctionDecls;
	}

	private var _cachedFieldDecls:Map<String, FieldDecl> = null;
	private var _cachedFunctionDecls:Map<String, FunctionDecl> = null;
	private var _cachedVarDecls:Map<String, VarDecl> = null;

	private function buildCaches()
	{
		_cachedFieldDecls = [];
		_cachedFunctionDecls = [];
		_cachedVarDecls = [];

		for (f in _c.fields)
		{
			_cachedFieldDecls.set(f.name, f);
			switch (f.kind)
			{
				case KFunction(fn):
					_cachedFunctionDecls.set(f.name, fn);
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					if (v.expr != null)
					{
						this._interp.variables.set(f.name, this._interp.expr(v.expr));
					}
				default:
					throw 'Unknown field kind: ${f.kind}';
			}
		}
	}
}


class TemplateClassBase {
	public function new() { }
}
@:hscriptClass
class TemplateClass extends TemplateClassBase implements hscript.HScriptedClass { } // TODO: Allow made hscriptedClass for non extenden class