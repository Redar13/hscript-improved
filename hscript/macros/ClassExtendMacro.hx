package hscript.macros;

#if macro
import haxe.macro.Type.ClassType;
import Type.ValueType;
import haxe.macro.Expr.Function;
import haxe.macro.Expr;
import haxe.macro.Type.MetaAccess;
import haxe.macro.Type.FieldKind;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.VarAccess;
import haxe.macro.*;
import hscript.custom_classes.HScriptedClassMacro;
import Sys;

using StringTools;
using Lambda;

@:access(hscript.custom_classes.HScriptedClassMacro)
class ClassExtendMacro {
	public static inline final FUNC_PREFIX = "_HX_SUPER__";
	public static inline final CLASS_SUFFIX = "_HSX";

	public static var unallowedMetas:Array<String> = [":hscriptClassPreProcessed", ":structInit", ":bitmap", ":noCustomClass", ":generic", "hscriptClassPreProcessed", ":hscriptClass"];

	public static var modifiedClasses:Array<String> = [];

	public static function init() {
		#if !display
		#if CUSTOM_CLASSES
		if(Context.defined("display")) return;
		for(apply in Config.ALLOWED_CUSTOM_CLASSES) {
			Compiler.addGlobalMetadata(apply, "@:build(hscript.macros.ClassExtendMacro.build())");
		}
		#end
		#end
	}

	// TODO?: Check if the class is completely written.
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var clRef = Context.getLocalClass();
		if (clRef == null || fields.length == 0) return fields;
		var cl = clRef.get();

		if (cl.isAbstract || cl.isExtern || cl.isFinal || cl.isInterface) return fields;
		if (!cl.name.endsWith("_Impl_") && !cl.name.endsWith(CLASS_SUFFIX) && !cl.name.endsWith("_HSC")) {
			if(cl.params.length > 0) // TODO
			{
				// trace(cl.module + "." + cl.name);
				// trace(cl.params);
				return fields;
			}

			for(m in cl.meta.get())
				if (unallowedMetas.contains(m.name))
					return fields;

			var key = cl.module;
			var fkey = cl.module + "." + cl.name;

			for (i in Config.DISALLOW_CUSTOM_CLASSES)
				if(fkey.startsWith(i) || key.startsWith(i))
					return fields;

			var _tempCl = cl;
			// trace(_tempCl.fields.get());
			var isNotStaticModule = _tempCl.constructor != null && _tempCl.fields.get().length > 0;
			while (!isNotStaticModule && _tempCl.superClass != null)
			{
				_tempCl = _tempCl.superClass.t.get();
				isNotStaticModule = _tempCl.constructor != null && _tempCl.fields.get().length > 0;
			}
			if(!isNotStaticModule || cl.params.length > 0) // doesn't compile static module or class with only static fields
				return fields;

			var shadowClass:TypeDefinition = macro class { };
			shadowClass.kind = TDClass({
				pack: cl.pack.copy(),
				name: cl.name
			}, [
				{name: "HScriptedClass", pack: ["hscript"]}
			], false, true, false);
			/*
			if (cl.params.length > 0)
			{
				shadowClass.kind.params = ;
			}
			*/
			shadowClass.name = '${cl.name}$CLASS_SUFFIX';
			shadowClass.meta = [
								{name: ":hscriptClass", pos: Context.currentPos()},
								{name: ":access", params: [macro ""], pos: Context.currentPos()}
							];

			var imports = Context.getLocalImports().copy();
			Utils.setupMetas(shadowClass, imports);
			/*
			for(e in cl.params) {
				shadowClass.fields.push({
					pos: Context.currentPos(),
					name: e.name,
					kind: FVar(null, Context.parseInlineString('@:privateAccess (${e.name})', Context.currentPos())),
					access: [APrivate]
				});
			}
			*/

			// trace(key);
			// trace(" " + fkey);
			Context.defineModule(cl.module, [shadowClass], imports);

			// trace(shadowClass.pack.join(".") + "." + shadowClass.name);
			// trace(cl.module + "." + shadowClass.name);
			// Compiler.addGlobalMetadata(cl.module + "." + shadowClass.name, "@:autoBuild(hscript.custom_classes.HScriptedClassMacro.build())");

			/*
			var key = cl.module;
			var fkey = cl.module + "." + cl.name;
			switch (key)
			{
				case "sys.thread.FixedThreadPool" // Error: Type name sys.thread.Worker_HSX is redefined from module sys.thread.
					| "StdTypes" | "Xml" | "Date" // Error: Cant extend basic class
					| "away3d.tools.commands.Mirror" // Error: Unknown identifier
					| "away3d.tools.commands.SphereMaker" // Error: Unknown identifier
					| "away3d.tools.commands.Weld" // Error: Unknown identifier
					| "sys.thread.EventLoop": // Error: cant override force inlined
						return fields;
			}
			if(fkey == "hscript.CustomClassHandler.TemplateClass") return fields; // Error: Redefined
			if(Config.DISALLOW_CUSTOM_CLASSES.contains(cl.module) || Config.DISALLOW_CUSTOM_CLASSES.contains(fkey)) return fields;
			if(cl.module.contains("_")) return fields; // Weird issue, sorry

			var shadowClass = macro class { };

			var definedFields:Array<String> = [];

			//trace(getModuleName(cl));

			var hasNew = false;

			for(_field in [fields.copy(), superFields.copy()])
			for(f in _field) {
				if (f == null)
					continue;
				if (f.name == "new") {
					hasNew = true;
					continue;
				}
				if (f.name.startsWith(FUNC_PREFIX))
					continue;
				if (f.access.contains(ADynamic) || f.access.contains(AStatic) || f.access.contains(AExtern) || f.access.contains(AInline))
					continue;

				if(f.name == "hget" || f.name == "hset") continue; // sorry, no overwriting the hget and hset in custom classes, yet
				if(definedFields.contains(f.name)) continue; // no duplicate fields

				for(m in f.meta)
					if (unallowedMetas.contains(m.name))
						continue;

				switch(f.kind) {
					case FFun(fun):
						if (fun == null)
							continue;
						if (fun.params != null && fun.params.length > 0) // TODO: Support for this maybe?
							continue;

						if(fun.params == null)
							fun.params = [];

						var overrideExpr:Expr;
						var returns:Bool = !fun.ret.match(TPath({name: "Void"}));

						var name = f.name;

						var arguments = fun.args == null ? [] : [for(a in fun.args) macro $i{a.name}];

						if (returns) {
							overrideExpr = macro {
								if (__custom__variables != null) {
									if(__custom__variables.exists($v{name})) {
										var v:Dynamic = null;
										if (Reflect.isFunction(v = __custom__variables.get($v{name}))) {
											return v($a{arguments});
										}
									}
								}
								return super.$name($a{arguments});
							};
						} else {
							overrideExpr = macro {
								if (__custom__variables != null) {
									if(__custom__variables.exists($v{name})) {
										var v:Dynamic = null;
										if (Reflect.isFunction(v = __custom__variables.get($v{name}))) {
											v($a{arguments});
											return;
										}
									}
								}
								super.$name($a{arguments});
							};
						}

						var superFuncExpr:Expr = returns ? {
							macro return super.$name($a{arguments});
						} : {
							macro super.$name($a{arguments});
						};

						var func:Function = {
							ret: fun.ret,
							params: fun.params.copy(),
							expr: overrideExpr,
							args: fun.args.copy()
						};

						var overrideField:Field = {
							name: f.name,
							access: f.access.copy(),
							kind: FFun(func),
							pos: Context.currentPos(),
							doc: f.doc,
							meta: f.meta.copy()
						};

						if (!overrideField.access.contains(AOverride))
							overrideField.access.push(AOverride);

						var superField:Field = {
							name: '$FUNC_PREFIX${f.name}',
							pos: Context.currentPos(),
							kind: FFun({
								ret: fun.ret,
								params: fun.params.copy(),
								expr: superFuncExpr,
								args: fun.args.copy()
							}),
							access: f.access.copy()
						};
						if (superField.access.contains(AOverride))
							superField.access.remove(AOverride);
						shadowClass.fields.push(overrideField);
						shadowClass.fields.push(superField);
						definedFields.push(f.name);
					default:
						// fuck off >:(

				}
			}

			var totalFields = definedFields.length;

			if(totalFields == 0 && !hasNew) {
				//Sys.println(cl.pack.join(".") + "." + cl.name + ", " + totalFields);
				return fields;
			}

			shadowClass.kind = TDClass({
				pack: cl.pack.copy(),
				name: cl.name
			}, [
				{name: "IHScriptCustomBehaviour", pack: ["hscript"]},
				{name: "IHScriptCustomClassBehaviour", pack: ["hscript"]}
			], false, true, false);
			shadowClass.name = '${cl.name}$CLASS_SUFFIX';
			var imports = Context.getLocalImports().copy();
			Utils.setupMetas(shadowClass, imports);
			Utils.processImport(imports, "hscript.UnsafeReflect", "UnsafeReflect");

			// Adding hscript getters and setters
			shadowClass.fields.push({
				name: "__interp",
				pos: Context.currentPos(),
				kind: FVar(TPath({
					pack: ['hscript'],
					name: 'Interp'
				})),
				access: [APublic]
			});

			shadowClass.fields.push({
				name: "__custom__variables",
				pos: Context.currentPos(),
				kind: FVar(TPath({
					pack: [],
					name: 'Map',
					params: [TPType(TPath({name: "String", pack: []})), TPType(TPath({name: "Dynamic", pack: []}))]
				})),
				access: [APublic]
			});

			shadowClass.fields.push({
				name: "__allowSetGet",
				pos: Context.currentPos(),
				kind: FVar(TPath({
					pack: [],
					name: 'Bool',
				}), macro true),
				access: [APublic]
			});

			shadowClass.fields.push({
				name: "__callGetter",
				pos: Context.currentPos(),
				kind: FFun({
					ret: TPath({name: 'Dynamic', pack: []}),
					params: [],
					expr: macro {
						__allowSetGet = false;
						var v = __custom__variables.get("get_" + name)();
						__allowSetGet = true;
						return v;
					},
					args: [
						{
							name: "name",
							opt: false,
							meta: [],
							type: TPath({name: "String", pack: []})
						}
					]
				}),
				access: [APublic]
			});

			shadowClass.fields.push({
				name: "__callSetter",
				pos: Context.currentPos(),
				kind: FFun({
					ret: TPath({name: 'Dynamic', pack: []}),
					params: [],
					expr: macro {
						__allowSetGet = false;
						var v = __custom__variables.get("set_" + name)(val);
						__allowSetGet = true;
						return v;
					},
					args: [
						{
							name: "name",
							opt: false,
							meta: [],
							type: TPath({name: "String", pack: []})
						},
						{
							name: "val",
							opt: false,
							meta: [],
							type: TPath({name: "Dynamic", pack: []})
						}
					]
				}),
				access: [APublic]
			});

			// Todo: make it possible to override
			if(cl.name == "FunkinShader" || cl.name == "CustomShader" || cl.name == "MultiThreadedScript") {
				Context.defineModule(cl.module, [shadowClass], imports);
				return fields;
			}

			var hasHgetInSuper = false;
			var hasHsetInSuper = false;

			if(cl.name == "CustomShader") {
				hasHgetInSuper = hasHsetInSuper = true;
			}

			// TODO: somehow check the super super class
			for(_field in [fields.copy(), superFields.copy()])
			for(f in _field) {
				if (f.name == "new")
					continue;
				if (f.name.startsWith(FUNC_PREFIX))
					continue;
				if (f.access.contains(ADynamic) || f.access.contains(AStatic) || f.access.contains(AExtern))
					continue;

				switch(f.kind) {
					case FFun(fun):
						if (fun.params != null && fun.params.length > 0)
							continue;

						if(!hasHgetInSuper)
							hasHgetInSuper = f.name == "hget";
						if(!hasHsetInSuper)
							hasHsetInSuper = f.name == "hset";

						if(hasHgetInSuper && hasHsetInSuper)
							break;
					default:

				}
			}

			var hgetField = if(hasHgetInSuper) {
				macro {
					if(__allowSetGet && __custom__variables.exists("get_" + name))
						return __callGetter(name);
					if (__custom__variables.exists(name))
						return __custom__variables.get(name);
					return super.hget(name);
				}
			} else {
				macro {
					if(__allowSetGet && __custom__variables.exists("get_" + name))
						return __callGetter(name);
					if (__custom__variables.exists(name))
						return __custom__variables.get(name);
					return Reflect.getProperty(this, name);
				}
			}

			var hsetField = if(hasHsetInSuper) {
				macro {
					if(__allowSetGet && __custom__variables.exists("set_" + name))
						return __callSetter(name, val);
					if (__custom__variables.exists(name)) {
						__custom__variables.set(name, val);
						return val;
					}
					return super.hset(this, name);
				}
			} else {
				macro {
					if(__allowSetGet && __custom__variables.exists("set_" + name))
						return __callSetter(name, val);
					if (__custom__variables.exists(name)) {
						__custom__variables.set(name, val);
						return val;
					}
					Reflect.setProperty(this, name, val);
					return Reflect.field(this, name);
				}
			}

			//if(hasHsetInSuper || hasHgetInSuper) return fields;

			//trace(cl.name);

			shadowClass.fields.push({
				name: "hset",
				pos: Context.currentPos(),
				access: hasHsetInSuper ? [AOverride, APublic] : [APublic],
				kind: FFun({
					ret: TPath({name: 'Dynamic', pack: []}),
					params: [],
					expr: hsetField,
					args: [
						{
							name: "name",
							opt: false,
							meta: [],
							type: TPath({name: "String", pack: []})
						},
						{
							name: "val",
							opt: false,
							meta: [],
							type: TPath({name: "Dynamic", pack: []})
						}
					]
				})
			});

			shadowClass.fields.push({
				name: "hget",
				pos: Context.currentPos(),
				access: hasHgetInSuper ? [AOverride, APublic] : [APublic],
				kind: FFun({
					ret: TPath({name: 'Dynamic', pack: []}),
					params: [],
					expr: hgetField,
					args: [
						{
							name: "name",
							opt: false,
							meta: [],
							type: TPath({name: "String", pack: []})
						}
					]
				})
			});
			*/

			/*var p = new Printer();
			var aa = p.printTypeDefinition(shadowClass);
			if(aa.length < 5024)
			trace(aa);
			if(aa.indexOf("pack") >= 0)
			if(cl.name == "FunkinShader")*/

			// Context.defineModule(cl.module, [shadowClass], imports);
		}

		return fields;
	}
}
#else
class ClassExtendMacro {
	public var usedClass:Class<Dynamic>;
	public var className:String;
}
#end