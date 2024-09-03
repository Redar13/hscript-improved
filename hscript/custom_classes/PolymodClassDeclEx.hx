package hscript.custom_classes;

import hscript.Expr.ClassDecl;

typedef ClassDeclEx =
{
	> ClassDecl,
	/**
	 * Save performance and improve sandboxing by resolving imports at interpretation time.
	 */
	//@:optional var imports:Map<String, Array<String>>;
	@:optional var imports:Map<String, ClassImport>;
	@:optional var pkg:Array<String>;
}

typedef ClassImport = {
	@:optional var name:String;
	@:optional var pkg:Array<String>;
	@:optional var fullPath:String; // pkg.pkg.pkg.name
	@:optional var cls:Class<Dynamic>;
	@:optional var enm:Enum<Dynamic>;
}
