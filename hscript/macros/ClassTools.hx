package hscript.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.TypeTools;
#end

class ClassTools
{
	macro static function build() 
	{
		static final thisName:String = 'hscript.macros.ClassTools';
		final self = TypeTools.getClass(Context.getType(thisName));
		Context.onGenerate(function(types) 
		{
			var names = [];
			
			for (t in types)
				switch t 
				{
					case TEnum(_.get() => c, _):
						if (c.name.indexOf("_Impl_") == -1)
							names.push(Context.makeExpr('${c.pack.join(".")}.${c.name}', c.pos));
					case TInst(_.get() => c, _):
						if (c.name.indexOf("_Impl_") == -1)
							names.push(Context.makeExpr('${c.pack.join(".")}.${c.name}', c.pos));
					default:
				}

			self.meta.remove('classes');
			self.meta.add('classes', names, self.pos);
		});
		return macro cast haxe.rtti.Meta.getType($p{thisName.split('.')});
	}

	public static final allClassesAvailable:Array<String> = #if macro [] #else build().classes #end;

}