package hscript.macros;

#if macro
import Type.ValueType;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Printer;
import haxe.macro.Compiler;

using StringTools;

class UsingHandler {
	public static function init() {
		#if !display
		if(Context.defined("display")) return;
		for(apply in Config.ALLOWED_ABSTRACT_AND_ENUM) {
			Compiler.addGlobalMetadata(apply, '@:build(hscript.macros.UsingHandler.build())');
		}
		#end
	}

	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var clRef = Context.getLocalClass();
		if (clRef == null) return fields;
		var cl = clRef.get();

		if (cl.name.endsWith("_Impl_") && cl.params.length <= 0 && !cl.meta.has(":multiType") && !cl.name.contains("_HSC")) {
			var trimEnum = cl.name.substr(0, cl.name.length - 6);

			var key = cl.module;
			var fkey = key + "." + trimEnum;
			if(key.contains("_")) return fields; // Weird issue, sorry
			switch (key)
			{
				case "lime.system.Locale" // Error: Unknown identifier : currentLocale, Due to Func
					| "cpp.Function" // Error: Unknown identifier : nativeGetProcAddress, Due to Func
					| "haxe.ds.Vector" // Error: haxe.ds._Vector.VectorData<blit.T> has no field blit, Due to Func
					| "haxe.display.Display" // Error: haxe.display.DisplayItemKind<haxe.display.DisplayLiteral<Dynamic>> has no field Null, Due to Func
					| "cpp.Callable" // Error: cpp.Function.fromStaticFunction must be called on static function, Due to Func
					| "haxe.display.JsonAnonStatusKind" // Error: cannot initialize a variable of type 'char *' with an rvalue of type 'const char *', Due to Func
					| "cpp.CharStar": // Error: cannot initialize a variable of type 'char *' with an rvalue of type 'const char *', Due to Func
						return fields;
			}
			for (i in Config.DISALLOW_ABSTRACT_AND_ENUM)
				if(fkey.startsWith(i) || key.startsWith(i))
					return fields;

			var shadowClass = macro class { };
			shadowClass.kind = TDClass();
			shadowClass.params = switch(cl.params.length) {
				case 0:
					null;
				/*
				case 1:
					[{
						name: "T",
					}];
				*/
				default:
					[for(k=>e in cl.params) {
						name: e.name
					}];
			}
			shadowClass.name = '${cl.name.substr(0, cl.name.length - 6)}_HSC';

			var imports = Context.getLocalImports().copy();
			Utils.setupMetas(shadowClass, imports);
			//trace(cl.module);

			for(f in fields)
				switch(f.kind) {
					case FFun(fun):
						/* // TODO: Allow non static functions
						if (f.access.contains(AMacro))
							continue;
						for (i in fun.args)
							if (i.type != null && i.type.match(TPath({name: "T"})))
								i.type = TPath({name: "Dynamic", pack:[]});
						*/
						// if (fun.ret.match(TPath({name: "T"})))
						// 	fun.ret = TPath({name: "Dynamic", pack:[]});
						// fun.ret = null;
						if (f.access.contains(AStatic))
						{
							if (fun.expr != null) {
								fun.expr = macro @:privateAccess $e{fun.expr};

								shadowClass.fields.push(f);

								/*var trimEnum = cl.name.substr(0, cl.name.length - 6);

								var returns:Bool = !fun.ret.match(TPath({name: "Void"}));

								var name = f.name;

								var arguments = fun.args == null ? [] : [for(a in fun.args) macro $i{a.name}];

								var expr:Expr = Context.parse('${returns?"return " : ""} $trimEnum.$name(${[for(a in fun.args) a.name].join(", ")})', f.pos);

								var func:Function = {
									ret: fun.ret,
									params: fun.params.copy(),
									expr: expr,
									args: fun.args.copy()
								};

								var field:Field = {
									pos: f.pos,
									name: f.name,
									meta: f.meta,
									kind: FFun(func),
									doc: null,//f.doc,
									access: [APublic, AStatic]
								}
								shadowClass.fields.push(field);*/
							}
						}
					case FProp(get, set, t, e):
						if (get == "default" && (set == "never" || set == "null")) {
							shadowClass.fields.push(f);
						}
					case FVar(t, e):
						if (f.access.contains(AStatic) || cl.meta.has(":enum") || f.name.toUpperCase() == f.name) {
							var name:String = f.name;
							var enumType:String = cl.name;
							var pack = cl.module.split(".");

							//trace(pack, cl.name, name, cl.module);

							if(pack[pack.length - 1] == trimEnum)
								pack.pop();

							var complexType:ComplexType = t;
							if(complexType == null && e != null) {
								complexType = switch(e.expr) {
									case EConst(CRegexp(_)): TPath({ name: "EReg", pack: [] });

									default: null;
								}
							}
							if(complexType == null) {
								complexType = TPath({
									name: trimEnum,
									pack: [],//pack
								});
							}

							var code = Context.parse('@:privateAccess ($trimEnum.$name)', f.pos); // '${pack.join(".")}.${trimEnum}.$name'

							var field:Field = {
								pos: f.pos,
								name: f.name,
								meta: f.meta,
								kind: FVar(null, code),
								doc: f.doc,
								access: [APublic, AStatic]
							}

							shadowClass.fields.push(field);
						}
					default:
				}

			//var printer = new Printer();
			//for(field in shadowClass.fields)
			//	trace(printer.printField(field));

			Context.defineModule(cl.module, [shadowClass], imports);
		}

		return fields;
	}
}
#end