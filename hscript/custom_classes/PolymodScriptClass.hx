package hscript.custom_classes;

#if hscript
import hscript.Expr;
import hscript.Printer;
import hscript.Interp;
import hscript.custom_classes.PolymodClassDeclEx;

using StringTools;

enum Param
{
	Unused;
}

/**
 * Grabbed from polymod
 * @see https://github.com/larsiusprime/polymod/tree/master/polymod/hscript
 */

/**
 * Provides handlers for scripted classes
 * Based on code by Ian Harrigan
 * @see https://github.com/ianharrigan/hscript-ex
 */
@:access(hscript.Interp)
@:allow(hscript.Interp)
class PolymodScriptClass
{
	/*
	 * STATIC VARIABLES
	 */
	private static final scriptInterp = new Interp(null, null);

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

	/*
	 * STATIC METHODS
	 */
	/**
	 * Register a scripted class by parsing the text of that script.
	 */
	static function registerScriptClassByString(body:String, path:String = null):Void
	{
		scriptInterp.addModule(body, path == null ? 'hscriptClass' : 'hscriptClass($path)');
	}

	/**
	 * Returns a list of all registered classes.
	 * @return Array<String>
	 */
	public static function listScriptClasses():Array<String>
	{
		var result = [];
		@:privateAccess
		for (key => _value in Interp._scriptClassDescriptors)
		{
			result.push(key);
		}
		return result;
	}

	/**
	 * Returns a list of all registered classes which extend the class specified by the given name.
	 * @return Array<String>
	 */
	public static function listScriptClassesExtending(clsPath:String):Array<String>
	{
		var result = [];
		@:privateAccess
		for (key => value in Interp._scriptClassDescriptors)
		{
			var superClasses = getSuperClasses(value);
			if (superClasses.indexOf(clsPath) != -1)
			{
				result.push(key);
			}
		}
		return result;
	}

	/**
	 * Returns a list of all registered classes which extend the specified class.
	 		* @param cls Any Class which you expect scripted classes to be extending.
	 * @return Array<String>
	 */
	static function listScriptClassesExtendingClass(cls:Class<Dynamic>):Array<String>
	{
		return listScriptClassesExtending(Type.getClassName(cls));
	}

	static function getSuperClasses(classDecl:ClassDeclEx):Array<String>
	{
		if (classDecl.extend == null)
		{
			// No superclasses.
			return [];
		}

		// Get the super class name.
		static var staticPrinter = new hscript.Printer();
		var extendString = staticPrinter.typeToString(classDecl.extend);
		// Prepend the package name.
		if (classDecl.pkg != null && extendString.indexOf('.') == -1)
		{
			var extendPkg = classDecl.pkg.join('.');
			extendString = '$extendPkg.$extendString';
		}

		// Check if the superclass is a scripted class.
		var classDescriptor:ClassDeclEx = Interp.findScriptClassDescriptor(extendString);

		if (classDescriptor != null)
		{
			// Parse the parent scripted class.
			return [extendString].concat(getSuperClasses(classDescriptor));
		}
		else
		{
			// Templates are ignored completely since there's no type checking in HScript.
			if (extendString.indexOf('<') != -1)
			{
				extendString = extendString.split('<')[0];
			}

			var superCls:Class<Dynamic> = null;

			if (classDecl.imports.exists(extendString))
			{
				var importedClass:ClassImport = classDecl.imports.get(extendString);
				if (importedClass != null && importedClass.cls == null) {
					// importedClass was defined but `cls` was null. This class must have been blacklisted.
					var clsName = classDecl.pkg != null ? '${classDecl.pkg.join('.')}.${classDecl.name}' : classDecl.name;
					return [];
				} else if (importedClass != null) {
					superCls = importedClass.cls;
				}
			}

			if (superCls == null) {
				// Check if the superclass is a native class.
				superCls = Type.resolveClass(extendString);
			}

			// Check if the superclass was resolved.
			if (superCls != null)
			{
				var result = [];
				// The superclass is a native class.
				while (superCls != null)
				{
					// Recursively add this class's superclasses.
					result.push(Type.getClassName(superCls));

					// This returns null when the class has no superclass.
					superCls = Type.getSuperClass(superCls);
				}
				return result;
			}
			else
			{
				return [];
			}
		}
	}

	public inline static function createScriptClassInstance(name:String, args:Array<Dynamic> = null):PolymodAbstractScriptClass
	{
		return Interp.createScriptClassInstance(name, args);
	}

	/**
	 * INSTANCE METHODS
	 */
	public function new(c:ClassDeclEx, args:Array<Dynamic>)
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
		_interp = new Interp(targetClass, this);
		_c = c;
		buildCaches();

		var ctorField = findField("new");
		if (ctorField != null)
		{
			callFunction("new", args);
			/*
			if (superClass == null && _c.extend != null)
			{
				// _interp.errorEx(EClassSuperNotCalled);
			}
			*/
		}
		else if (_c.extend != null)
		{
			createSuperClass(args);
		}
	}

	var __superClassFieldList:Array<String> = null;

	public function superHasField(name:String):Bool
	{
		if (superClass == null)
			return false;
		// Reflect.hasField(this, name) is REALLY expensive so we use a cache.
		if (__superClassFieldList == null)
		{
			__superClassFieldList = Reflect.fields(superClass).concat(Type.getInstanceFields(Type.getClass(superClass)));
		}
		return __superClassFieldList.indexOf(name) != -1;
	}

	private function createSuperClass(args:Array<Dynamic> = null)
	{
		if (args == null)
		{
			args = [];
		}

		var fullExtendString = new hscript.Printer().typeToString(_c.extend);

		// Templates are ignored completely since there's no type checking in HScript.
		if (fullExtendString.indexOf('<') != -1)
		{
			fullExtendString = fullExtendString.split('<')[0];
		}

		// Build an unqualified path too.
		var fullExtendStringParts = fullExtendString.split('.');
		var extendString = fullExtendStringParts[fullExtendStringParts.length - 1];

		var classDescriptor = Interp.findScriptClassDescriptor(extendString);
		if (classDescriptor != null)
		{
			var abstractSuperClass:PolymodAbstractScriptClass = new PolymodScriptClass(classDescriptor, args);
			superClass = abstractSuperClass;
		}
		else
		{
			var clsToCreate:Class<Dynamic> = null;

			if (scriptClassOverrides.exists(fullExtendString)) {
				clsToCreate = scriptClassOverrides.get(fullExtendString);

				if (clsToCreate == null)
				{
					// @:privateAccess _interp.errorEx(EClassUnresolvedSuperclass(fullExtendString, 'WHY?'));
				}
			} else if (_c.imports.exists(extendString)) {
				clsToCreate = _c.imports.get(extendString).cls;

				if (clsToCreate == null)
				{
					// _interp.errorEx(EClassUnresolvedSuperclass(extendString, 'target class blacklisted'));
				}
			} else {
				// _interp.errorEx(EClassUnresolvedSuperclass(extendString, 'missing import'));
			}

			superClass = Type.createInstance(clsToCreate, args);
		}
	}

	@:privateAccess(hscript.Interp)
	public function callFunction(fnName:String, args:Array<Dynamic> = null):Dynamic
	{
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
			var fn = Reflect.field(superClass, fixedName);
			/*
			if (fn == null)
			{
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while calling function super.${fnName}(): EInvalidAccess' + '\n' +
					'InvalidAccess error: Super function "${fnName}" does not exist! Define it or call the correct superclass function.');
			}
			*/
			r = Reflect.callMethod(superClass, fn, fixedArgs);
		}
		return r;
	}

	private var _c:ClassDeclEx;
	private var _interp:Interp;

	public var superClass:Dynamic = null;

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
		createSuperClass(args);
	}

	/**
	 * Search for a function field with the given name.
	 * @param name The name of the function to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findFunction(name:String, cacheOnly:Bool = true):Null<FunctionDecl>
	{
		if (_cachedFunctionDecls != null)
		{
			return _cachedFunctionDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				switch (f.kind)
				{
					case KFunction(fn):
						return fn;
					case _:
				}
			}
		}

		return null;
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

	/**
	 * Search for a variable field with the given name.
	 * @param name The name of the variable to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findVar(name:String, cacheOnly:Bool = false):Null<VarDecl>
	{
		if (_cachedVarDecls != null)
		{
			_cachedVarDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				switch (f.kind)
				{
					case KVar(v):
						return v;
					case _:
				}
			}
		}

		return null;
	}

	/**
	 * Search for a field (function OR variable) with the given name.
	 * @param name The name of the field to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findField(name:String, cacheOnly:Bool = true):Null<FieldDecl>
	{
		if (_cachedFieldDecls != null)
		{
			return _cachedFieldDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				return f;
			}
		}
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
						var varValue = this._interp.expr(v.expr);
						this._interp.variables.set(f.name, varValue);
					}
				default:
					throw 'Unknown field kind: ${f.kind}';
			}
		}
	}
}
#end
