package hscript.macros;

import haxe.io.Bytes;
#if macro
import haxe.Serializer;
import haxe.crypto.Base64;
import haxe.macro.Type.BaseType;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.TypeTools;
import haxe.macro.Type;
#else
import haxe.Resource;
import haxe.Unserializer;
import haxe.rtti.Meta;
#end

class ClassTools
{
	inline static final classPath = 'hscript.macros.ClassTools';
	public static final allClassesAvailable:Array<String> = #if macro
		[];
	#else
		{
			var finalArr:Array<String> = null;
			try
			{
				finalArr = Unserializer.run(Resource.getBytes('$classPath::allClassesAvailable').toString());
			}
			catch(e)
			{
				trace(e);
				finalArr = [];
			}
			finalArr;
		}
	#end
	public static final typedefDefines:Map<String,String> = #if macro
		[];
	#else
		{
			var finalMap:Map<String,String> = null;
			try
			{
				finalMap = Unserializer.run(Resource.getBytes('$classPath::typedefDefines').toString());
			}
			catch(e)
			{
				trace(e);
				finalMap = [];
			}
			finalMap;
		}
	#end

	#if macro
	static function getModulePath(t:BaseType):String
		return t.pack.length > 0 ? '${t.pack.join(".")}.${t.name}' : t.name;

	static function isValidName(n:String):Bool
		return n != "T" && n.indexOf("_Impl_") == -1 && n.indexOf("_HSX") != n.length - 4
	;
	public static function init()
	{
		if(Context.defined("display")) return;

		function onGenerate(t:Type)
		{
			switch t
			{
				case TMono(c):
					if (c != null)
					{
						onGenerate(c.get());
					}
				case TEnum(_.toString() => c, _):
					allClassesAvailable.push(c);
				case TInst(_.toString() => c, _):
					allClassesAvailable.push(c);
				case TType(_.get() => c, _):
					switch c.type
					{
						case TEnum(_.get() => mainCl, _):
							if (isValidName(mainCl.name))
							{
								typedefDefines.set(getModulePath(c), getModulePath(mainCl));
							}
						case TInst(_.get() => mainCl, _):
							if (isValidName(mainCl.name))
							{
								typedefDefines.set(getModulePath(c), getModulePath(mainCl));
							}
						default:
					}
					if (isValidName(c.name))
					{
						allClassesAvailable.push(getModulePath(c));
					}
				/*
				case TAbstract(t, _params):
					var abstractPath = t.toString();
					if (t.get().impl != null)
					{
						allClassesAvailable.push(abstractPath);
					}
				*/
				default:
			}
		}

		Context.onGenerate(function(types:Array<Type>)
		{
			for (t in types) onGenerate(t);

			function runSerialize(v:Dynamic) {
				var s = new Serializer();
				s.serialize(v);
				return s.toString();
			}
			Context.addResource('$classPath::typedefDefines', Bytes.ofString(runSerialize(typedefDefines)));
			Context.addResource('$classPath::allClassesAvailable', Bytes.ofString(runSerialize(allClassesAvailable)));
		});
	}
	#end
}