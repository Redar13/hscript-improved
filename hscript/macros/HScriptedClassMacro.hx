package hscript.macros;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

class HScriptedClassMacro
{
	static var secondaryPassInitialized:Bool = false;

	/**
	 * The first step creates the interface functions.
	 * The second build step (called in an onAfterTyping callback) creates the rest of the functions,
	 *   which require initial typing to be completed before they can be created.
	 */
	public static macro function build():Array<Field>
	{
		var cls:ClassType = Context.getLocalClass().get();

		if (cls.meta.get().find(m -> return m.name == 'hscriptClassPreProcessed') == null)
		{
			// Context.info('HScriptedClass: Class ' + cls.name + ' ready to pre-process...', Context.currentPos());
			var fields:Array<Field> = Context.getBuildFields().copy();

			// trace('    ${cls.name}');
			if (cls.superClass != null)
			{
				fields = fields.concat(buildScriptedClassUtils(cls, cls.superClass.t.get()));
			}

			fields = buildHScriptClass(cls, fields);

			// Ensure unused scripted classes are still available to initialize in scripts.
			// SORRY, DCE gets run before this, so we can't use the @:keep metadata.
			cls.meta.add("hscriptClassPreProcessed", [], cls.pos);
			// trace('  ${cls.name}');
			// trace('  ${[for (i in fields) i.name]}');
			return fields;
		}
		else
		{
			// Already processed.
		}

		// Returning null is equal to "don't do anything".
		return null;
	}

	/**
	 * Parse `@:hscriptClass`.
	 */
	static function parseHScriptClassParams(metaEntry:MetadataEntry):HScriptClassParams
	{
		var result:HScriptClassParams = {};

		switch (metaEntry.params[0].expr)
		{
			case EObjectDecl(paramFields):
				// paramFields
				for (paramField in paramFields)
				{
					switch (paramField.field)
					{
						case 'baseClass':
							switch (paramField.expr.expr)
							{
								case EConst(CIdent(baseClassName)):
									result.baseClass = baseClassName;
								default:
									Context.error("Error: @:hscriptClass baseClass must be a string", Context.currentPos());
							}
							break;
					}
				}
			default:
				Context.error("Error: @:hscriptClass({}) must contain an object", Context.currentPos());
		}

		return result;
	}

	/**
	 * Create the complicated parts of the generated class,
	 * specifically the `__hsx_init()` function and the override methods.
	 */
	public static function buildHScriptClass(cls:ClassType, fields:Array<Field>):Array<Field>
	{

		// var cls:ClassType = Context.getLocalClass().get();

		var script_class_meta = cls.meta.get().find(function(m) return m.name == ':hscriptClass');
		// trace(cls.meta);
		if (script_class_meta != null)
		{
			var superCls:ClassType = cls.superClass == null ? null : cls.superClass.t.get();

			// Create scripted class override for constructor.
			var constructor = fields.find(function(field) return field.name == 'new');

			// trace(cls.name);
			if (constructor != null)
			{
				Context.error("Error: Constructor already defined for this class", Context.currentPos());
			}
			else if (superCls != null)
			{
				if (superCls.constructor != null)
				{
					// Context.follow(superCls.constructor.get().type);
					switch (superCls.constructor.get().type)
					{
						case TFun(args, ret):
							// Build a new constructor, which has the same signature as the superclass constructor.
							// var constArgs = [
							// 	for (arg in args)
							// 		{name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
							// ];
							var initField:Field = buildScriptedClassInit(cls, superCls, []);
							fields.push(initField);
							// constructor = buildScriptedClassConstructor(constArgs);
						case TLazy(builder):
							switch (builder())
							{
								case TFun(args, ret):
									// Build a new constructor, which has the same signature as the superclass constructor.
									// var constArgs = [
									// 	for (arg in args)
									// 		{name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
									// ];
									var initField:Field = buildScriptedClassInit(cls, superCls, []);
									fields.push(initField);
									// constructor = buildScriptedClassConstructor(constArgs);
								case builtValue:
									Context.error('Error: Lazy superclass constructor is not a function (got ${builtValue})', Context.currentPos());
							}
						case superClsConstType:
							Context.error('Error: super constructor is not a function (got ${superClsConstType})', Context.currentPos());
					}
				}
				else
				{
					constructor = buildEmptyScriptedClassConstructor();
					// Create scripted class utility functions.
					// Context.info('  Creating scripted class utils...', Context.currentPos());
					var initField:Field = buildScriptedClassInit(cls, superCls, []);
					fields.push(initField);
					fields.push(constructor);
				}
			}
			else
			{
				constructor = buildEmptyScriptedClassConstructor();
				// Create scripted class utility functions.
				// Context.info('  Creating scripted class utils...', Context.currentPos());
				var initField:Field = buildScriptedClassInit(cls, null, []);
				fields.push(initField);
				fields.push(constructor);
			}

			// Create scripted class overrides for all fields (except constructor).
			// Create scripted class overrides for non-constructor fields.
			fields = fields.concat(buildScriptedClassFieldOverrides(cls));
		}
		// Else, do nothing.

		return fields;
	}

	static function buildScriptedClassInit(cls:ClassType, superCls:ClassType, superConstArgs:Array<FunctionArg>):Field
	{
		var clsTypeName:String = cls.pack.join('.');
		if (clsTypeName != "")
		{
			clsTypeName += '.${cls.name}';
		}
		else
		{
			clsTypeName = cls.name;
		}
		// Context.info('  Building scripted class __hsx_init() function', Context.currentPos());

		// trace(clsTypeName);
		return {
			name: "__hsx_init",
			doc: "Initializes a scripted class instance using the given scripted class name and constructor arguments.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [
					{name: 'clsName', type: Context.toComplexType(Context.getType('String'))},
					{name: 'interp', type: Context.toComplexType(Context.getType('hscript.Interp'))},
					{name: 'args', opt: true, type: Context.toComplexType(Context.getType('Array'))},
				],
				params: null,
				ret: Context.toComplexType(Context.getType(clsTypeName)),
				expr: macro
				{
					// trace('  Init $clsName class');
					var asc:hscript.custom_classes.PolymodAbstractScriptClass = hscript.custom_classes.PolymodScriptClass.createScriptClassInstance(clsName, interp, args);
					if (asc == null)
					{
						// trace('  Failed init $clsName class');
						// polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + ')');
						return null;
					}
					return asc.superClass;
				},
			}),
		};
	}

	static function buildScriptedClassUtils(cls:ClassType, superCls:ClassType):Array<Field>
	{
		/*
		var function_scriptGet:Field = {
			name: 'scriptGet',
			doc: 'Retrieves the value of a local variable of a scripted class.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [{name: 'varName', type: Context.toComplexType(Context.getType('String'))}],
				params: null,
				ret: Context.toComplexType(Context.getType('Dynamic')),
				expr: macro
				{
					return _asc.fieldRead(varName);
				},
			}),
		}

		var function_scriptSet:Field = {
			name: 'scriptSet',
			doc: 'Directly modifies the value of a local variable of a scripted class.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [
					{name: 'varName', type: Context.toComplexType(Context.getType('String'))},
					{
						name: 'varValue',
						type: Context.toComplexType(Context.getType('Dynamic')),
						value: macro null,
					}
				],
				params: null,
				ret: Context.toComplexType(Context.getType('Dynamic')),
				expr: macro
				{
					return _asc.fieldWrite(varName, varValue);
				},
			}),
		}

		var function_scriptCall:Field = {
			name: 'scriptCall',
			doc: 'Calls a function of the scripted class with the given name and arguments.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [
					{name: 'funcName', type: Context.toComplexType(Context.getType('String'))},
					{
						name: 'funcArgs',
						type: toComplexTypeArray(Context.toComplexType(Context.getType('Dynamic'))),
						value: macro null,
					}
				],
				params: null,
				ret: Context.toComplexType(Context.getType('Dynamic')),
				expr: macro
				{
					return _asc.callFunction(funcName, funcArgs == null ? [] : funcArgs);
				},
			}),
		};
		return [
			var__asc,
			function_scriptCall,
			function_scriptGet,
			function_scriptSet
		];
		*/

		var var__asc:Field = {
			name: "_asc",
			doc: "The AbstractScriptClass instance which any variable or function calls are redirected to internally.",
			access: [APrivate], // Private instance variable
			kind: FVar(Context.toComplexType(Context.getType('hscript.custom_classes.PolymodAbstractScriptClass'))),
			pos: cls.pos,
		};
		return [
			var__asc
		];
	}

	/**
	 * For each function in the superclass, create a function in the subclass
	 		* that redirects to the internal abstract script class.
	 */
	static function buildScriptedClassFieldOverrides(cls:ClassType):Array<Field>
	{
		var fieldDone:Array<String> = [];
		var fieldArray:Array<Field> = [];

		var targetClass:ClassType = cls;
		var mappedParams:Map<String, Type> = new Map<String, Type>();
		var tType = Context.getType(cls.name);
		var tClass = Context.toComplexType(tType);

		// Start with a custom implementation of .toString()
		var func_toString:Array<Field> = buildScriptedClass_toString(targetClass);
		if (func_toString != null)
		{
			for (i in func_toString)
				fieldArray.push(i);
		}
		fieldDone.push('toString');

		while (targetClass != null && (targetClass.params == null || targetClass.params.length == 0))
		{
			// Context.info('Processing overrides for class: ${targetClass.name}<${mappedParams}>', Context.currentPos());
			// Values will be either of type haxe.macro.Expr.Field or Bool. This is because setting a Map value to null removes the key.
			for (newFieldName => newField in buildScriptedClassFieldOverrides_inner(targetClass, mappedParams))
			{
				if (Std.isOfType(newField, Bool))
				{
					// Sometimes a child version needs to be skipped but the parent version doesn't.
					// In this case, the parent needs to be skipped also.
					// Example: A child function override can be inline when the parent isn't.
					fieldDone.push(newFieldName);
				}
				else
				{
					if (!fieldDone.contains(newFieldName))
					{
						fieldArray.push(newField);
						fieldDone.push(newFieldName);
					}
					else
					{
						// Context.info('  Redundant: ${newField.name}', Context.currentPos());
					}
				}
			}
			if (targetClass.superClass != null)
			{
				var targetParams:Array<Type> = targetClass.superClass.params;
				targetClass = targetClass.superClass.t.get();
				for (paramIndex in 0...targetClass.params.length)
				{
					var paramType = targetParams[paramIndex];
					var paramName = targetClass.params[paramIndex].name;
					var paramFullName = '${targetClass.pack.join('.')}.${targetClass.name}.${paramName}';
					mappedParams.set(paramFullName, paramType);
				}
			}
			else
			{
				targetClass = null;
			}
		}

		return fieldArray;
	}

	static function buildScriptedClass_toString(cls:ClassType):Array<Field>
	{
		var oldToString = cls.fields.get().find(i -> return i.name == "toString");
		var _tempSuperCl = cls;
		while (oldToString == null && _tempSuperCl.superClass != null)
		{
			_tempSuperCl = _tempSuperCl.superClass.t.get();
			oldToString = _tempSuperCl.fields.get().find(i -> return i.name == "toString");
		}
		if (oldToString != null && oldToString.kind.match(FMethod(MethInline)))
			return null;
		var access = [APublic];
		if (oldToString != null)
			access.push(AOverride);

		var funcs = [{
			name: '__hsx_super_to_string_', // huh, "__hsx_super_toString" is like a duplicate field
			doc: null,
			access: [APrivate],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [],
				params: null,
				ret: Context.toComplexType(Context.getType('String')),
				expr: macro
				{
					$
					{
						if (oldToString == null)
						(
							macro return $v{cls.name}
						)
						else
						(
							macro return super.toString()
						)
					}
				},
			}),
		},
		{
			name: 'toString',
			doc: null,
			access: access,
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [],
				params: null,
				ret: Context.toComplexType(Context.getType('String')),
				expr: macro
				{
					if (_asc == null)
					{
						return this.__hsx_super_to_string_();
					}
					else
					{
						return _asc.callFunction('toString');
					}
				},
			}),
		}];

		return funcs;
	}

	static function buildScriptedClassFieldOverrides_inner(cls:ClassType, targetParams:Map<String, Type>):Map<String, Dynamic>
	{
		// Values will be either of type haxe.macro.Expr.Field or Bool. This is because setting a Map value to null removes the key.
		var fields:Map<String, Dynamic> = new Map<String, Dynamic>();

		for (field in cls.fields.get())
		{
			if (field.name == 'new')
			{
				// Do nothing
			}
			else
			{
				var results:Array<Field> = overrideField(field, targetParams);
				if (results == null || results.length == 0)
				{
					fields.set(field.name, false);
				}
				else
				{
					for (result in results)
					{
						fields.set(result.name, result);
					}
				}
			}
		}
		for (field in cls.statics.get())
		{
			// Context.info('  Skipping: ${field.name} is static', Context.currentPos());
		}
		// trace(fields);
		return fields;
	}

	static function getBaseParamsOfType(parentType:Type, paramTypes:Array<Type>):Array<TypeParameter>
	{
		var parentParams:Array<TypeParameter> = [];

		switch (parentType)
		{
			case TMono(_.get() => ty):
				return getBaseParamsOfType(ty, paramTypes);

			case TInst(t, params):
				// Continue
				parentParams = t.get().params;

			case TType(_.get().type => ty, params):
				// Recurse
				return getBaseParamsOfType(ty, paramTypes);

			case TDynamic(t):
				// Recurse
				return getBaseParamsOfType(t, paramTypes);

			case TLazy(_() => ty):
				// Recurse
				return getBaseParamsOfType(ty, paramTypes);

			case TAbstract(t, _params):
				// Continue
				parentParams = t.get().params;

			// case TEnum(t:Ref<EnumType>, params:Array<Type>):
			// case TFun(args:Array<{name:String, opt:Bool, t:Type}>, ret:Type):
			// case TAnonymous(a:Ref<AnonType>):
			default:
				Context.error('Unsupported type: $parentType', Context.currentPos());
		}

		var result:Array<TypeParameter> = [];

		for (i => parentParam in parentParams)
		{
			var newParam:TypeParameter = {
				name: parentParam.name,
				t: paramTypes[i],
			};
			result.push(newParam);
		}

		return result;
	}

	static function scanBaseTypes(targetType:Type):Array<Type>
	{
		switch (targetType)
		{
			case TFun(args, ret):
				var results:Array<Type> = [];

				for (result in scanBaseTypes(ret))
				{
					results.push(result);
				}
				for (arg in args)
				{
					for (result in scanBaseTypes(arg.t))
					{
						results.push(result);
					}
				}
				return results;
			case TAbstract(ty, params):
				if (params.length == 0)
				{
					return [targetType];
				}
				else
				{
					var results:Array<Type> = [];
					for (param in params)
					{
						for (result in scanBaseTypes(param))
						{
							results.push(result);
						}
					}
					return results;
				}
			default:
				return [targetType];
		}
	}

	/**
	 * Insert real types into a parameterized type.
	 * For example, `TypeA<TypeB<TypeC<T>>>` becomes `TypeA<TypeB<TypeC<int>>>` if T is `int`.
	 *
	 * Note, function runs recursively.
	 */
	static function deparameterizeType(targetType:Type, targetParams:Map<String, Type>):Type
	{
		var resultType:Type = targetType;

		switch (targetType)
		{
			case TFun(args, ret):
				// Function type.
				// This is not referring to functions of a class, but rather a function taken as a parameter (like a callback).

				// Deparameterize the return type.
				var retType:Type = deparameterizeType(ret, targetParams);
				// Deparameterize the argument types.
				var argTypes:Array<{name:String, opt:Bool, t:Type}> = args.map(function(arg)
				{
					return {
						name: arg.name,
						opt: arg.opt,
						t: deparameterizeType(arg.t, targetParams),
					};
				});

				// Construct the new type.
				resultType = TFun(argTypes, retType);

			case TAbstract(ty, params):
				// Abstract type. Sometimes used by types like Null<T>.

				var name = ty.toString();

				// trace(name);
				// Check if the Abstract type is a parameter we recognize and can replace.
				if (targetParams.exists(name))
				{
					// If so, replace it with the real type.
					resultType = targetParams.get(name);
				}
				else if (params.length != 0)
				{
					var oldParams:Array<Type> = [];
					var newParams:Array<Type> = [];
					for (param in params)
					{
						var baseTypes = scanBaseTypes(param);

						for (baseType in baseTypes)
						{
							var newParam = deparameterizeType(baseType, targetParams);
							if (newParam.toString() == "Void")
							{
								// Skipping Void...
							}
							else
							{
								oldParams.push(baseType);
								newParams.push(newParam);
							}
						}
					}
					var baseParams = getBaseParamsOfType(resultType, oldParams);
					newParams = newParams.slice(0, baseParams.length);

					if (newParams.length > 0)
					{
						// Context.info('Building new abstract (${baseParams} + ${newParams})...', Context.currentPos());
						resultType = resultType.applyTypeParameters(baseParams, newParams);
						// Context.info('Deparameterized abstract type: ${resultType.toString()}', Context.currentPos());
					}
					else
					{
						// Leave the type as is.
					}
				}
				else
				{
					// Else, there are no parameters related this type and we don't need to mutate it.
				}
			case TInst(ty, params):
				// Instance type. Used by most variables.

				var name = ty.toString();

				// trace(name);
				// Check if the Instance type is a parameter we recognize and can replace.
				if (targetParams.exists(name))
				{
					// If so, replace it with the real type.
					resultType = targetParams.get(name);
				}
				else if (params.length != 0)
				{
					var oldParams:Array<Type> = [];
					var newParams:Array<Type> = [];
					for (param in params)
					{
						var baseTypes = scanBaseTypes(param);

						for (baseType in baseTypes)
						{
							var newParam = deparameterizeType(baseType, targetParams);
							if (newParam.toString() == "Void")
							{
								// Skipping Void...
							}
							else
							{
								oldParams.push(baseType);
								newParams.push(newParam);
							}
						}
					}
					var baseParams = getBaseParamsOfType(resultType, oldParams);
					newParams = newParams.slice(0, baseParams.length);

					if (newParams.length > 0)
					{
						// Context.info('Building new abstract (${baseParams} + ${newParams})...', Context.currentPos());
						resultType = resultType.applyTypeParameters(baseParams, newParams);
						// Context.info('Deparameterized abstract type: ${resultType.toString()}', Context.currentPos());
					}
					else
					{
						// Leave the type as is.
					}
				}
				else
				{
					// Else, there are no parameters related this type and we don't need to mutate it.
				}

			default:
				// Do nothing.
				// Muted because I haven't actually seen any issues caused by this. Maybe investigate in the future.
				// Context.warning('You failed to handle this! ${targetType}', Context.currentPos());
		}

		return resultType;
	}

	/**
	 * Given a ClassField from the target class, create one or more Fields that override the target field,
	 * redirecting any calls to the internal AbstractScriptedClass.
	 */
	static function overrideField(field:ClassField, targetParams:Map<String, Type>, ?type:Type = null):Array<Field>
	{
		if (type == null)
		{
			type = field.type;
		}

		switch (type)
		{
			case TLazy(lt):
				// A lazy wrapper for another field.
				// We have to call the function to get the true value.
				return overrideField(field, targetParams, lt());
			case TFun(args, ret):
				if (field.params.length > 0) // nah i give up | TODO
				{
					// trace(field.name);
					// trace(field.params);
					return null;
				}
				if (field.isFinal)
				{
					// Context.info('  Skipping: "${field.name}" is final function', Context.currentPos());
					// func_access.push(AFinal);
					return null;
				}

				if (!field.kind.match(FMethod(MethNormal)))
					return null;

				/*
				// We need to skip overriding functions which are inline.
				// Normal Haxe classes can't override these functions anyway, so we can skip them.
				switch (field.kind)
				{
					case FMethod(k):
						switch (k)
						{
							case MethNormal: // Do nothing.
							default: return null;
						}
				*/
				/*
				case FMethod(k):
					switch (k)
					{
						case MethInline:
							// Context.info('  Skipping: "${field.name}" is inline function', Context.currentPos());
							return null;
						case MethDynamic:
							// Context.info('  Skipping: "${field.name}" is dynamic function', Context.currentPos());
							return null;
						case MethMacro:
							// Context.info('  Skipping: "${field.name}" is macro function', Context.currentPos());
							return null;
						default: // Do nothing.
					}
				*/
				/*
					default:
						return null;
				}
				*/

				// This field is a function of the class.
				// We need to redirect to the scripted class in case our scripted class overrides it.
				// If it isn't overridden, the AbstractScriptClass will call the original function.

				// We need to skip overriding functions which meet have a private type as an argument.
				// Normal Haxe classes can't override these functions anyway, so we can skip them.
				for (arg in args)
				{
					switch (arg.t)
					{
						case TInst(ty, pa):
							var typ = ty.get();
							if (typ != null && typ.isPrivate)
							{
								// Context.info('  Skipping: "${field.name}" contains private type ${typ.module}.${typ.name}', Context.currentPos());
								return null;
							}
						default: // Do nothing.
					}
				}

				// Skip overriding functions which are Generics.
				// This is because this actually creates several different functions at compile time.
				// TODO: Can we somehow override these functions?
				// trace(field.name);
				for (fieldMeta in field.meta.get())
				{
					if (fieldMeta.name == ":generic" || fieldMeta.name == ":unreflective")
					{
						// Context.info('  Skipping: "${field.name}" is marked with @:generic or @:unreflective', Context.currentPos());
						return null;
					}
				}

				// We only get limited information about the args from Type, we need to use TypedExprDef.

				if (field == null || field.expr() == null)
				{
					// Context.info('  Skipping: "${field.name}" is not an expression', Context.currentPos());
					return null;
				}

				var func_inputArgs:Array<FunctionArg> = [];

				var func_access = [AOverride];
				if (field.isPublic)
				{
					func_access.push(APublic);
				}
				else
				{
					func_access.push(APrivate);
				}

				switch (field.expr().expr)
				{
					case TFunction(tfunc):
						// Create an array of FunctionArg from the TFunction's argument objects.
						// Context.info('  Processing args of function "${field.name}"', Context.currentPos());
						for (arg in tfunc.args)
						{
							// Whether the argument is optional.
							var isOptional = (arg.value == null);

							var val:Expr = arg.value == null ? null : Context.getTypedExpr(arg.value);
							var type:Null<ComplexType> = Context.toComplexType(arg.v.t);

							func_inputArgs.push({
								name: arg.v.name,
								// type: type,
								type: Context.toComplexType(deparameterizeType(arg.v.t, targetParams)),
								// opt: isOptional,
								meta: arg.v.meta.get(),
								value: val,
							});
						}
					case TConst(tcon):
						// Okay, so uh, this is actually a VARIABLE storing a function.
						// Don't attempt to re-define it.

						return null;
					default:
						Context.warning('Expected a function and got ${field.expr().expr}', Context.currentPos());
				}

				// Is there a better way to do this?
				var doesReturnVoid:Bool = ret.toString() == "Void";

				// Generate the list of call arguments for the function.
				// Context.info('${args}', Context.currentPos());
				// var func_callArgs:Array<Expr> = [for (arg in args) macro $i{arg.name}];
				var func_callArgs:Array<Expr> = [for (arg in func_inputArgs) macro $i{arg.name}];
				// trace(func_inputArgs);

				// if (field.params.length > 0)
				// {
				// 	// trace('${field.name}:\n\t\t${field.params} -> ${func_params}\n\t${func_callArgs}');
				// 	trace('${field.name}: ${[for (i in func_inputArgs) i.name]}');
				// }
				// Context.info('  Processing return of function "${field.name}"', Context.currentPos());
				// var func_ret = doesReturnVoid ? null : Context.toComplexType(deparameterizeType(ret, targetParams));
				//  var func_ret = doesReturnVoid ? null : Context.toComplexType(Context.follow(ret));

				var funcName:String = field.name;
				var func_over:Field = {
					name: funcName,
					doc: field.doc == null ? 'Polymod HScriptedClass override of ${funcName}.' : 'Polymod HScriptedClass override of ${funcName}.\n${field.doc}',
					access: func_access,
					meta: field.meta.get(),
					pos: field.pos,
					kind: FFun({
						args: func_inputArgs,
						// params: func_params,
						// ret: func_ret,
						expr: macro
						{
							if (_asc == null)
							{
								// Fallback, call the original function.
								$
								{
									doesReturnVoid ? (
										macro super.$funcName($a{func_callArgs})
									) : (
										macro return super.$funcName($a{func_callArgs})
									)
								}
							}
							else
							{
								// trace('ASC: Calling $v{funcName}() in macro-generated function...');
								$
								{
									doesReturnVoid ? (
										macro _asc.callFunction($v{funcName}, [$a{func_callArgs}])
									) : (
										macro return _asc.callFunction($v{funcName}, [$a{func_callArgs}])
									)
								}
							}
						},
					}),
				};
				var func_superCall:Field = {
					name: "__hsx_super_" + funcName,
					doc: 'Calls the original ${field.name} function while ignoring the ScriptedClass override.',
					access: [APrivate],
					meta: field.meta.get(),
					pos: field.pos,
					kind: FFun({
						args: func_inputArgs,
						// params: func_params,
						// ret: func_ret,
						expr: macro
						{
							// var fieldName:String = $v{funcName};
							// Fallback, call the original function.
							// trace('ASC: Force call to super ${fieldName}');
							$
							{
								doesReturnVoid ? (
									macro super.$funcName($a{func_callArgs})
								) : (
									macro return super.$funcName($a{func_callArgs})
								)
							}
						},
					}),
				}

				return [func_over, func_superCall];
			case TInst(_t, _params):
				// This field is an instance of a class.
				// Example: var test:TestClass = new TestClass();

				// Originally, I planned to replace all variables on the class with properties,
				// however this is not possible because properties are merely a compile-time feature.

				// However, since scripted classes correctly access the superclass variables anyway,
				// there is no need to override the value.
				// Context.info('Field: Instance variable "${field.name}"', Context.currentPos());
				return null;
			case TEnum(_t, _params):
				// Enum instance
				// Context.info('Field: Enum variable "${field.name}"', Context.currentPos());
				return null;
			case TMono(_t):
				// Monomorph instance
				// https://haxe.org/manual/types-monomorph.html
				// Context.info('Field: Monomorph variable "${field.name}"', Context.currentPos());
				return null;
			case TAnonymous(_t):
				// Context.info('Field: Anonymous variable "${field.name}"', Context.currentPos());
				return null;
			case TDynamic(_t):
				// Context.info('Field: Dynamic variable "${field.name}"', Context.currentPos());
				return null;
			case TAbstract(_t, _params):
				// Context.info('Field: Abstract variable "${field.name}"', Context.currentPos());
				return null;
			default:
				// Context.info('Unknown field type: ${field}', Context.currentPos());
				return null;
		}
	}

	static function buildScriptedClassConstructor(superConstArgs:Array<FunctionArg>):Field
	{
		var constArgs:Array<FunctionArg> = superConstArgs;
		var superCallArgs:Array<Expr> = [for (arg in superConstArgs) macro $i{arg.name}];

		// Context.info('  Generating constructor for scripted class with super(${superCallArgs})', Context.currentPos());

		return {
			name: 'new',
			access: [APrivate],
			pos: Context.currentPos(),
			kind: FFun({
				args: superConstArgs,
				expr: macro
				{
					// Call the super constructor with appropriate args
					super($a{superCallArgs});
				},
			}),
		};
	}

	/**
	 * Create the type corresponding to an array of the given type.
	 * For example, toComplexTypeArray(String) will return Array<String>.
	 */
	static function toComplexTypeArray(inputType:ComplexType):haxe.macro.ComplexType
	{
		var typeParams = (inputType != null) ? [TPType(inputType)] : [
			TPType(TPath({
				pack: [],
				name: 'Dynamic',
				sub: null,
				params: []
			}))
		];

		var result:ComplexType = TPath({
			pack: [],
			name: 'Array',
			sub: null,
			params: typeParams,
		});

		return result;
	}

	static function buildEmptyScriptedClassConstructor():Field
	{
		return {
			name: "new",
			access: [APrivate],
			pos: Context.currentPos(),
			kind: FFun({
				args: [],
				expr: macro
				{
				}
			})
		};
	}
}

typedef HScriptClassParams =
{
	?baseClass:String,
}
