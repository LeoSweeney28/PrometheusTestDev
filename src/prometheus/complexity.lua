-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- complexity.lua
--
-- This Script provides expression complexity transformations - wrapping simple expressions
-- in complex-looking but semantically equivalent computations.

local logger = require("logger");
local Ast = require("prometheus.ast");

local Complexity = {};

local random = math.random;

-- Wrap a number in complex arithmetic that yields the same result
function Complexity.complexifyNumber(numExpr)
	local choice = random(1, 4);
	if choice == 1 then
		return Ast.AddExpression(Ast.MulExpression(numExpr, Ast.NumberExpression(1)), Ast.NumberExpression(0));
	elseif choice == 2 then
		return Ast.DivExpression(numExpr, Ast.NumberExpression(1));
	elseif choice == 3 then
		return Ast.SubExpression(numExpr, Ast.NumberExpression(0));
	end

	return Ast.MulExpression(Ast.AddExpression(numExpr, Ast.NumberExpression(0)), Ast.NumberExpression(1));
end

-- Wrap a string in complex-looking but valid AST forms
function Complexity.complexifyString(strExpr)
	if random(1, 3) == 1 then
		return Ast.StrCatExpression(strExpr, Ast.StringExpression(""));
	end

	return Ast.StrCatExpression(Ast.StringExpression(""), strExpr);
end

-- Wrap a variable in a safe no-op expression
function Complexity.complexifyVariable(varExpr)
	return Ast.OrExpression(Ast.BooleanExpression(false), varExpr);
end

-- Create a "junk" variable that's computed but never used
function Complexity.injectJunkComputation(scope)
	if not scope then
		return nil;
	end

	local junkVar = scope:addVariable("_junk" .. tostring(math.random(100000, 999999)));
	local junkOperations = {
		Ast.AddExpression(Ast.NumberExpression(math.random(1, 100)), Ast.NumberExpression(math.random(1, 100))),
		Ast.MulExpression(Ast.NumberExpression(math.random(1, 10)), Ast.NumberExpression(math.random(1, 10))),
		Ast.StrCatExpression(Ast.StringExpression("junk"), Ast.StringExpression("")),
	};

	return Ast.LocalVariableDeclaration(scope, { junkVar }, { junkOperations[math.random(1, #junkOperations)] });
end

-- Wrap a simple boolean condition in complex logic
function Complexity.complexifyCondition(condExpr)
	local choice = random(1, 3);
	if choice == 1 then
		return Ast.OrExpression(condExpr, Ast.BooleanExpression(false));
	elseif choice == 2 then
		return Ast.AndExpression(condExpr, Ast.BooleanExpression(true));
	end

	return Ast.NotExpression(Ast.NotExpression(condExpr));
end

-- Create a complex statement block that's semantically a no-op
function Complexity.createJunkStatements(count, scope)
	count = count or 3;
	local statements = {};

	for i = 1, count do
		if scope and random() > 0.65 then
			table.insert(statements, Ast.LocalVariableDeclaration(scope, { scope:addVariable("_x" .. i) }, { Ast.NumberExpression(i) }));
		elseif random() > 0.5 then
			table.insert(statements, Ast.DoStatement(Ast.Block({}, scope)));
		else
			table.insert(statements, Ast.DoStatement(Ast.Block({}, scope)));
		end
	end

	return statements;
end

-- Wrap code in unnecessary scope layers
function Complexity.wrapInUnnecessaryScopes(block, depth)
	depth = depth or 1;
	local result = block;

	for i = 1, depth do
		result = Ast.Block({ Ast.DoStatement(result) }, result.scope);
	end

	return result;
end

-- Create a dummy guard that is valid for the AST API
function Complexity.createDummyGuard(scope)
	if not scope then
		return {
			declaration = Ast.DoStatement(Ast.Block({})),
			check = Ast.DoStatement(Ast.Block({})),
		};
	end

	local guardVar = scope:addVariable("_guard" .. tostring(math.random(100000, 999999)));
	local guardValue = math.random(0, 1) == 0;

	return {
		declaration = Ast.LocalVariableDeclaration(scope, { guardVar }, { Ast.BooleanExpression(guardValue) }),
		check = Ast.AndExpression(Ast.BooleanExpression(true), Ast.VariableExpression(scope, guardVar)),
	};
end

return Complexity;
