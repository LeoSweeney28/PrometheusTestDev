-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- AstBuilder.lua
--
-- This Script provides builder functions for common AST construction patterns.
-- Reduces duplication across steps that build complex AST structures.

local Ast = require("prometheus.ast");
local AstKind = Ast.AstKind;

local AstBuilder = {};

-- Predicate builders (commonly used in OpaquePredicates and ControlFlow steps)
function AstBuilder:truePredicate()
	local variant = math.random(1, 4);
	
	if variant == 1 then
		local a = math.random(2, 128);
		return Ast.EqualsExpression(
			Ast.SubExpression(Ast.NumberExpression(a + 1), Ast.NumberExpression(1), false),
			Ast.NumberExpression(a),
			false
		);
	elseif variant == 2 then
		local a = math.random(2, 32);
		return Ast.GreaterThanExpression(
			Ast.AddExpression(Ast.NumberExpression(a), Ast.NumberExpression(1), false),
			Ast.NumberExpression(a),
			false
		);
	elseif variant == 3 then
		local a = math.random(3, 97);
		return Ast.EqualsExpression(
			Ast.ModExpression(Ast.NumberExpression(a * 3), Ast.NumberExpression(a), false),
			Ast.NumberExpression(0),
			false
		);
	else
		local a = math.random(4, 64);
		return Ast.NotExpression(
			Ast.NotEqualsExpression(Ast.NumberExpression(a), Ast.NumberExpression(a), false),
			false
		);
	end
end

function AstBuilder:complexTruePredicate(depth)
	depth = depth or 1;
	local base = self:truePredicate();
	
	if depth <= 1 then
		return base;
	end
	
	if depth == 2 then
		if math.random() < 0.5 then
			return Ast.AndExpression(base, self:truePredicate(), false);
		else
			return Ast.NotExpression(Ast.NotExpression(base, false), false);
		end
	end
	
	if math.random() < 0.5 then
		return Ast.OrExpression(
			base,
			Ast.EqualsExpression(Ast.NumberExpression(1), Ast.NumberExpression(2), false),
			false
		);
	else
		return Ast.AndExpression(
			Ast.NotExpression(Ast.NotExpression(base, false), false),
			self:truePredicate(),
			false
		);
	end
end

-- Expression builders
function AstBuilder:numericExpression(value)
	return Ast.NumberExpression(value);
end

function AstBuilder:stringExpression(value)
	return Ast.StringExpression(value);
end

function AstBuilder:booleanExpression(value)
	return Ast.BooleanExpression(value);
end

function AstBuilder:binaryOp(kind, lhs, rhs)
	if kind == "add" or kind == AstKind.AddExpression then
		return Ast.AddExpression(lhs, rhs, false);
	elseif kind == "sub" or kind == AstKind.SubExpression then
		return Ast.SubExpression(lhs, rhs, false);
	elseif kind == "mul" or kind == AstKind.MulExpression then
		return Ast.MulExpression(lhs, rhs, false);
	elseif kind == "div" or kind == AstKind.DivExpression then
		return Ast.DivExpression(lhs, rhs, false);
	elseif kind == "mod" or kind == AstKind.ModExpression then
		return Ast.ModExpression(lhs, rhs, false);
	elseif kind == "pow" or kind == AstKind.PowExpression then
		return Ast.PowExpression(lhs, rhs, false);
	elseif kind == "and" or kind == AstKind.AndExpression then
		return Ast.AndExpression(lhs, rhs, false);
	elseif kind == "or" or kind == AstKind.OrExpression then
		return Ast.OrExpression(lhs, rhs, false);
	elseif kind == "concat" or kind == AstKind.StrCatExpression then
		return Ast.StrCatExpression(lhs, rhs, false);
	end
	error("Unknown binary operator: " .. tostring(kind));
end

function AstBuilder:comparison(kind, lhs, rhs)
	if kind == "eq" or kind == AstKind.EqualsExpression then
		return Ast.EqualsExpression(lhs, rhs, false);
	elseif kind == "neq" or kind == AstKind.NotEqualsExpression then
		return Ast.NotEqualsExpression(lhs, rhs, false);
	elseif kind == "lt" or kind == AstKind.LessThanExpression then
		return Ast.LessThanExpression(lhs, rhs, false);
	elseif kind == "gt" or kind == AstKind.GreaterThanExpression then
		return Ast.GreaterThanExpression(lhs, rhs, false);
	elseif kind == "lte" or kind == AstKind.LessThanOrEqualsExpression then
		return Ast.LessThanOrEqualsExpression(lhs, rhs, false);
	elseif kind == "gte" or kind == AstKind.GreaterThanOrEqualsExpression then
		return Ast.GreaterThanOrEqualsExpression(lhs, rhs, false);
	end
	error("Unknown comparison operator: " .. tostring(kind));
end

function AstBuilder:unaryOp(kind, operand)
	if kind == "not" or kind == AstKind.NotExpression then
		return Ast.NotExpression(operand, false);
	elseif kind == "negate" or kind == AstKind.NegateExpression then
		return Ast.NegateExpression(operand, false);
	elseif kind == "len" or kind == AstKind.LenExpression then
		return Ast.LenExpression(operand, false);
	end
	error("Unknown unary operator: " .. tostring(kind));
end

-- Control flow builders
function AstBuilder:ifBlock(condition, body, elseBody, scope)
	scope = scope or require("prometheus.scope"):new();
	return Ast.IfStatement(condition, body, {}, elseBody);
end

function AstBuilder:doBlock(statements, scope)
	scope = scope or require("prometheus.scope"):new();
	return Ast.DoStatement(Ast.Block(statements, scope));
end

function AstBuilder:whileBlock(condition, body, scope)
	scope = scope or require("prometheus.scope"):new();
	return Ast.WhileStatement(body, condition, scope);
end

-- Table builders
function AstBuilder:tableConstructor(entries)
	return Ast.TableConstructorExpression(entries or {});
end

function AstBuilder:tableEntry(value)
	return Ast.TableEntry(value);
end

function AstBuilder:keyedTableEntry(key, value)
	return Ast.KeyedTableEntry(key, value);
end

-- Function call builders
function AstBuilder:functionCall(base, args)
	return Ast.FunctionCallExpression(base, args or {});
end

function AstBuilder:methodCall(base, method, args)
	return Ast.PassSelfFunctionCallExpression(base, method, args or {});
end

-- Index builders
function AstBuilder:index(table_, index)
	return Ast.IndexExpression(table_, index);
end

-- Inversion utilities (commonly used in BooleanExpressionInversion)
function AstBuilder:invertComparison(comparisonNode)
	local inverseMap = {
		[AstKind.EqualsExpression] = Ast.NotEqualsExpression;
		[AstKind.NotEqualsExpression] = Ast.EqualsExpression;
		[AstKind.LessThanExpression] = Ast.GreaterThanOrEqualsExpression;
		[AstKind.GreaterThanExpression] = Ast.LessThanOrEqualsExpression;
		[AstKind.LessThanOrEqualsExpression] = Ast.GreaterThanExpression;
		[AstKind.GreaterThanOrEqualsExpression] = Ast.LessThanExpression;
	};
	
	local inverseFactory = inverseMap[comparisonNode.kind];
	if inverseFactory then
		return Ast.NotExpression(inverseFactory(comparisonNode.lhs, comparisonNode.rhs, false), false);
	end
	return comparisonNode;
end

function AstBuilder:invertLogic(logicNode)
	if logicNode.kind == AstKind.AndExpression then
		return Ast.NotExpression(
			Ast.OrExpression(
				Ast.NotExpression(logicNode.lhs, false),
				Ast.NotExpression(logicNode.rhs, false),
				false
			),
			false
		);
	elseif logicNode.kind == AstKind.OrExpression then
		return Ast.NotExpression(
			Ast.AndExpression(
				Ast.NotExpression(logicNode.lhs, false),
				Ast.NotExpression(logicNode.rhs, false),
				false
			),
			false
		);
	end
	return logicNode;
end

return AstBuilder;
