package hscript.macros;

import haxe.macro.Type.BaseType;
#if macro
import haxe.macro.Context;
import haxe.macro.TypeTools;
import haxe.macro.Type;
#else
import haxe.rtti.Meta;
#end

class ClassTools
{
	public static final allClassesAvailable:Array<String> = #if macro
		[];
	#else
		cast Meta.getType(ClassTools).allClassesAvailable;
	#end
	public static final typedefDefines:Map<String,String> = #if macro
		[];
	#else
		[for (i in cast (Meta.getType(ClassTools).typedefDefines, Array<Dynamic>)) i[0] => i[1]];
	#end

	static function getModulePath(t:BaseType):String
		return t.pack.length > 0 ? '${t.pack.join(".")}.${t.name}' : t.name;

	static function isValidName(n:String):Bool
		return n != "T" && n.indexOf("_Impl_") == -1 && n.indexOf("_HSX") != n.length - 4
	;
	public static function init()
	{
		#if (!display && macro)
		function onGenerate(t:Type)
		{
			switch t
			{
				case TMono(c):
					if (t != null)
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
				default:
			}
		}
		final self = TypeTools.getClass(Context.getType('hscript.macros.ClassTools'));
		Context.onGenerate(function(types:Array<Type>)
		{
			for (t in types)
				onGenerate(t);
			self.meta.remove('typedefDefines');
			self.meta.remove('allClassesAvailable');

			self.meta.add('typedefDefines', [for (name => orig in typedefDefines) macro [$v{name}, $v{orig}]], Context.currentPos());
			self.meta.add('allClassesAvailable', [for (i in allClassesAvailable) macro $v{i}], Context.currentPos());
		});
		#end
	}
}