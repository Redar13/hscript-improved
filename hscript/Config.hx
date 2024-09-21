package hscript;

class Config {
	// Runs support for custom classes in these
	public static final ALLOWED_CUSTOM_CLASSES = [
		// FLIXEL
		"flixel",
		// "flixel.tweens",	"flixel.text",		"flixel.sound",		"flixel.path",
		// "flixel.math",		"flixel.group",		"flixel.effects",	"flixel.animation",
	];

	// Runs support for abstract support in these
	public static final ALLOWED_ABSTRACT_AND_ENUM = [
		"flixel",
		"openfl.display.BlendMode",
	];

	// Incase any of your files fail
	// These are the module names
	public static final DISALLOW_CUSTOM_CLASSES = [
		"game.backend.utils",
		"flixel.addons.display.FlxSpriteAniRot",
		"flixel.addons.display.FlxShaderMaskCamera",
		"flixel.addons.display.FlxStarField",
		"flixel.addons.display.FlxZoomCamera",
		"flixel.system",
		"flixel.tweens",
		// "flixel.util",
		"flixel.system.macros",
		// "flixel.tile",
		"flixel.input",
		// "flixel.animation.FlxBaseAnimation",
		// "flixel.animation.FlxPrerotatedAnimation",
		// "flixel.effects.particles.FlxParticle",
		// "flixel.text.FlxText",
		// "away3d.extrusions.PathExtrude"
	];

	public static final DISALLOW_ABSTRACT_AND_ENUM = [
		"flixel.utils.FlxSignal",
	];
}