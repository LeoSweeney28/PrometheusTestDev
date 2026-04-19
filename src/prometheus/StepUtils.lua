-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- StepUtils.lua
--
-- This Script provides shared utility functions for obfuscation steps to reduce code duplication.

local StepUtils = {};

-- Common settings descriptors that multiple steps use
StepUtils.CommonSettings = {
	Threshold = {
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	};
	NestingDepth = {
		type = "number",
		default = 1,
		min = 1,
		max = 3,
	};
	MaxWrappers = {
		type = "number",
		default = 1,
		min = 1,
		max = 3,
	};
	IncludeNoise = {
		type = "boolean",
		default = true,
	};
	WrapInBlock = {
		type = "boolean",
		default = true,
	};
};

-- Random selection utilities
function StepUtils:randomBool(probability)
	return math.random() < (probability or 0.5);
end

function StepUtils:randomChoice(choices)
	if not choices or #choices == 0 then
		return nil;
	end
	return choices[math.random(1, #choices)];
end

function StepUtils:randomRange(min, max)
	if min > max then
		min, max = max, min;
	end
	return math.random(min, max);
end

function StepUtils:shuffle(tbl)
	for i = #tbl, 2, -1 do
		local j = math.random(i);
		tbl[i], tbl[j] = tbl[j], tbl[i];
	end
	return tbl;
end

-- Threshold-based filtering
function StepUtils:passThreshold(threshold)
	return math.random() <= threshold;
end

-- Table/collection utilities
function StepUtils:contains(tbl, value)
	for _, v in ipairs(tbl) do
		if v == value then
			return true;
		end
	end
	return false;
end

function StepUtils:findInTable(tbl, predicate)
	for k, v in pairs(tbl) do
		if predicate(k, v) then
			return k, v;
		end
	end
	return nil, nil;
end

function StepUtils:mapTable(tbl, fn)
	local result = {};
	for k, v in pairs(tbl) do
		result[k] = fn(v, k);
	end
	return result;
end

function StepUtils:filterTable(tbl, predicate)
	local result = {};
	for k, v in pairs(tbl) do
		if predicate(v, k) then
			result[k] = v;
		end
	end
	return result;
end

-- Scope utilities (commonly used in steps)
function StepUtils:createChildScope(parentScope)
	local Scope = require("prometheus.scope");
	return Scope:new(parentScope);
end

function StepUtils:createNoiseBlock(parentScope, blockContent)
	local Ast = require("prometheus.ast");
	local Scope = require("prometheus.scope");
	local noiseScope = Scope:new(parentScope);
	local body = blockContent or {Ast.NopStatement()};
	return Ast.Block(body, noiseScope);
end

-- Pattern check utilities
function StepUtils:isWrappableStatement(statement, allowControlFlow)
	local AstKind = require("prometheus.ast").AstKind;
	local kind = statement.kind;
	
	if kind == AstKind.LocalVariableDeclaration
		or kind == AstKind.LocalFunctionDeclaration
		or kind == AstKind.FunctionDeclaration then
		return false;
	end
	
	if not allowControlFlow then
		if kind == AstKind.ReturnStatement
			or kind == AstKind.IfStatement
			or kind == AstKind.WhileStatement
			or kind == AstKind.RepeatStatement
			or kind == AstKind.ForStatement
			or kind == AstKind.ForInStatement
			or kind == AstKind.BreakStatement
			or kind == AstKind.ContinueStatement then
			return false;
		end
	end
	
	return true;
end

function StepUtils:isExpression(node)
	return node and node.isExpression;
end

function StepUtils:isStatement(node)
	return node and node.isStatement;
end

function StepUtils:isBinaryExpression(node)
	if not node then return false; end
	local AstKind = require("prometheus.ast").AstKind;
	local kind = node.kind;
	return kind == AstKind.AddExpression
		or kind == AstKind.SubExpression
		or kind == AstKind.MulExpression
		or kind == AstKind.DivExpression
		or kind == AstKind.ModExpression
		or kind == AstKind.PowExpression
		or kind == AstKind.AndExpression
		or kind == AstKind.OrExpression;
end

function StepUtils:isComparisonExpression(node)
	if not node then return false; end
	local AstKind = require("prometheus.ast").AstKind;
	local kind = node.kind;
	return kind == AstKind.EqualsExpression
		or kind == AstKind.NotEqualsExpression
		or kind == AstKind.LessThanExpression
		or kind == AstKind.GreaterThanExpression
		or kind == AstKind.LessThanOrEqualsExpression
		or kind == AstKind.GreaterThanOrEqualsExpression;
end

function StepUtils:isUnaryExpression(node)
	if not node then return false; end
	local AstKind = require("prometheus.ast").AstKind;
	local kind = node.kind;
	return kind == AstKind.NotExpression
		or kind == AstKind.NegateExpression
		or kind == AstKind.LenExpression;
end

-- Numeric utilities
function StepUtils:randomInteger(min, max)
	return math.floor(self:randomRange(min, max));
end

function StepUtils:randomDecimal(min, max, decimals)
	decimals = decimals or 2;
	local factor = 10 ^ decimals;
	return math.floor(math.random() * (max - min) * factor + min * factor) / factor;
end

return StepUtils;
