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
						var pathNames: Array<String> = c.pack.copy();
						pathNames.push(c.name);
						names.push(Context.makeExpr(pathNames.join("."), c.pos));
					case TInst(_.get() => c, _):
						var pathNames: Array<String> = c.pack.copy();
						pathNames.push(c.name);
						names.push(Context.makeExpr(pathNames.join("."), c.pos));
					default:
				}

			self.meta.remove('classes');
			self.meta.add('classes', names, self.pos);
		});
		return macro cast haxe.rtti.Meta.getType($p{thisName.split('.')});
	}

	#if !macro
	public static final allClassesAvailable:List<String> = {
		var r:Array<String> = build().classes;
		var map = new List<String>();

		for (i in r) 
		{
			if (i.indexOf('_Impl_') == -1) // Check non private class
			{
				if (!(Type.resolveClass(i) == null && Type.resolveEnum(i) == null)) map.push(i);
			}
		}

		// trace(map);
		map;
	}
	#end
}