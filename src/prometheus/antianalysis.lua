-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- antianalysis.lua
--
-- This Script provides anti-analysis techniques to confuse static analysis tools and decompilers.

local Ast = require("prometheus.ast");

local AntiAnalysis = {};
local decoySequence = 0;

local function pickDeterministic(list)
	decoySequence = decoySequence + 1;
	return list[((decoySequence - 1) % #list) + 1];
end

local function safeBlock(statements, scope)
	return Ast.Block(statements or {}, scope);
end

-- Insert code that appears to have side effects but doesn't.
function AntiAnalysis.createFakeDataFlow()
	return {
		Ast.DoStatement(safeBlock({})),
		Ast.DoStatement(safeBlock({})),
	};
end

-- Create conditional code paths that appear to have different behavior
-- but actually execute the same code.
function AntiAnalysis.createMaskedConditional(realCode)
	return Ast.IfStatement(
		Ast.BooleanExpression(true),
		realCode,
		{},
		safeBlock({})
	);
end

-- Inject fake error handling that's never triggered.
function AntiAnalysis.injectFakeErrorHandling(realCode)
	return {
		Ast.DoStatement(safeBlock({})),
		realCode,
	};
end

-- Create code that appears to use external state but doesn't.
function AntiAnalysis.createFakeExternalDependency()
	local statements = {};
	for i = 1, 3 do
		table.insert(statements, Ast.IfStatement(Ast.BooleanExpression(false), safeBlock({}), {}, safeBlock({})));
	end
	return statements;
end

-- Create variable names that suggest hidden meaning.
function AntiAnalysis.generateMisdirectingName()
	local prefixes = { "_", "__", "___" };
	local middles = {
		"protected", "private", "internal", "hidden", "secret",
		"core", "base", "root", "main", "key", "token", "data"
	};
	local suffixes = { "_", "_v", "_impl", "_core", "_real" };

	decoySequence = decoySequence + 1;
	return prefixes[((decoySequence - 1) % #prefixes) + 1]
		.. middles[((decoySequence * 3 - 1) % #middles) + 1]
		.. tostring(100 + (decoySequence % 900))
		.. suffixes[((decoySequence * 7 - 1) % #suffixes) + 1];
end

local function makeUniqueDecoyName(scope)
	local baseName = AntiAnalysis.generateMisdirectingName();
	if not scope or not scope.variablesLookup then
		return baseName;
	end

	local candidate = baseName;
	for i = 1, 10 do
		if scope.variablesLookup[candidate] == nil then
			return candidate;
		end
		candidate = baseName .. "_" .. tostring(i);
	end

	return baseName .. "_" .. tostring(1000 + (decoySequence % 9000));
end

-- Create structure that looks like it's checking for debugging.
function AntiAnalysis.createDebugCheck()
	return Ast.IfStatement(
		Ast.BooleanExpression(true),
		safeBlock({ Ast.DoStatement(safeBlock({})) }),
		{},
		safeBlock({})
	);
end

-- Create structure that appears to use reflection/introspection.
function AntiAnalysis.createFakeReflection()
	return {
		Ast.DoStatement(safeBlock({})),
		Ast.DoStatement(safeBlock({})),
	};
end

-- Insert code that appears obfuscated but is actually readable.
function AntiAnalysis.createMaskedCodePath()
	return {
		Ast.DoStatement(safeBlock({})),
		Ast.DoStatement(safeBlock({})),
	};
end

-- Generate variable that looks important but isn't.
function AntiAnalysis.createDecoyVariable(scope)
	local decoyName = makeUniqueDecoyName(scope);

	if not scope then
		return {
			name = decoyName,
			var = nil,
			declaration = Ast.DoStatement(safeBlock({})),
		};
	end

	local decoyVar = scope:addVariable(decoyName);
	return {
		name = decoyName,
		var = decoyVar,
		declaration = Ast.LocalVariableDeclaration(
			scope,
			{ decoyVar },
			{ Ast.FunctionCallExpression(Ast.FunctionLiteralExpression({}, safeBlock({ Ast.ReturnStatement({ Ast.BooleanExpression(true) }) })), {}) }
		),
	};
end

-- Create comments that look like code but are actually comments.
function AntiAnalysis.createCodeLikeComment()
	local fakeCode = {
		"-- local secret = 0x" .. string.format("%x", 3735928559 + decoySequence),
		"-- _decrypt(" .. tostring(1000 + decoySequence) .. ", " .. tostring(2000 + decoySequence) .. ")",
		"-- if _isDebugging then _exit() end",
		"-- _validateSignature(" .. tostring(100000 + decoySequence) .. ")",
	};

	return pickDeterministic(fakeCode);
end

-- Inject fake version/capability checks.
function AntiAnalysis.createFakeVersionCheck()
	return Ast.IfStatement(
		Ast.LessThanExpression(Ast.NumberExpression(5), Ast.NumberExpression(6)),
		safeBlock({ Ast.DoStatement(safeBlock({})) }),
		{},
		safeBlock({})
	);
end

return AntiAnalysis;
