package hscript;

interface IHScriptCustomBehaviour {
	public function hset(name:String, val:Dynamic):Dynamic;
	public function hget(name:String):Dynamic;
	public function hExistsOnGet(name:String):Bool;
	public function hExistsOnSet(name:String):Bool;
}