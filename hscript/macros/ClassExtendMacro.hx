package hscript.macros;

#if macro
import haxe.macro.Type;
import Type.ValueType;
import haxe.macro.Expr;
import haxe.macro.*;
import hscript.macros.HScriptedClassMacro;
import Sys;

using StringTools;
using Lambda;
#end

@:access(hscript.macros.HScriptedClassMacro)
class ClassExtendMacro {
	public static final FUNC_PREFIX:String = "_HX_SUPER__";
	public static final CLASS_SUFFIX:String = "_HSX";

	#if macro
	public static var unallowedMetas:Array<String> = ["hscriptClassPreProcessed", ":structInit", ":bitmap", ":noCustomClass", ":generic", ":hscriptClass"];

	public static var modifiedClasses:Array<String> = [];

	public static function init():Void {
		#if !display
		#if CUSTOM_CLASSES
		if(Context.defined("display")) return;
		for(apply in Config.ALLOWED_CUSTOM_CLASSES) {
			Compiler.addGlobalMetadata(apply, "@:build(hscript.macros.ClassExtendMacro.build())");
		}
		#end
		#end
	}

	// TODO: Allows to extend a class with parameters.
	public static function build():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		var clRef:Null<haxe.macro.Type.Ref<ClassType>> = Context.getLocalClass();
		if (clRef == null || fields.length == 0) return fields;
		var cl:ClassType = clRef.get();

		if (
			cl.isAbstract || cl.isExtern || cl.isFinal || cl.isInterface
			|| cl.name.endsWith("_Impl_") || cl.name.endsWith("_HSC")
			|| cl.name.endsWith(CLASS_SUFFIX)
		)
			return fields;

		if(cl.params.length > 0) // TODO
		{
			// trace(cl.module + "." + cl.name);
			// trace(cl.params);
			return fields;
		}

		for(m in cl.meta.get())
			if (unallowedMetas.contains(m.name))
				return fields;

		var key:String = cl.module;
		var fkey:String = cl.module + "." + cl.name;

		for (i in Config.DISALLOW_CUSTOM_CLASSES)
			if(fkey.startsWith(i) || key.startsWith(i))
				return fields;

		var _tempCl:ClassType = cl;
		var isStaticModule:Bool = _tempCl.init == null && fields.filter(i -> return (i.access.contains(AStatic) || i.access.contains(AMacro))).length == 0;
		// var isStaticModule:Bool = _tempCl.init == null && _tempCl.fields.get()length == 0;
		while (isStaticModule && _tempCl.superClass != null)
		{
			_tempCl = _tempCl.superClass.t.get();
			isStaticModule = _tempCl.init == null && _tempCl.fields.get().length == 0;
		}
		if(isStaticModule) // doesn't compile static module or class with only staticfields
		{
			return fields;
		}

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

		var imports:Array<ImportExpr> = Context.getLocalImports().copy();
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
		// Compiler.addGlobalMetadata(cl.module + "." + shadowClass.name, "@:autoBuil(hscript.custom_classes.HScriptedClassMacro.build())");

		/*
		var p = new Printer();
		var aa = p.printTypeDefinition(shadowClass);
		if(aa.length < 5024)
		trace(aa);
		if(aa.indexOf("pack") >= 0)
		*/
		return fields;
	}
	#end
}