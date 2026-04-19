-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- IndirectFunctionCalls.lua
--
-- This Script provides an Obfuscation Step that adds call indirection.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitAst = require("prometheus.visitast")

local AstKind = Ast.AstKind

local IndirectFunctionCalls = Step:extend()
IndirectFunctionCalls.Description = "Wraps function call targets in indirection expressions"
IndirectFunctionCalls.Name = "Indirect Function Calls"

IndirectFunctionCalls.SettingsDescriptor = {
	Threshold = {
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	IncludeStatements = {
		type = "boolean",
		default = true,
	},
	IncludeExpressions = {
		type = "boolean",
		default = true,
	},
	IncludePassSelf = {
		type = "boolean",
		default = true,
	},
	IndirectionLayers = {
		type = "number",
		default = 1,
		min = 1,
		max = 3,
	},
	NonConstantIndex = {
		type = "boolean",
		default = true,
	},
}

function IndirectFunctionCalls:init(_) end

local function buildIndirectBase(baseExpression)
	return Ast.IndexExpression(
		Ast.TableConstructorExpression({
			Ast.TableEntry(baseExpression),
		}),
		Ast.NumberExpression(1)
	)
end

local function buildIndexExpression(nonConstant)
	if not nonConstant then
		return Ast.NumberExpression(1)
	end

	local lhs = math.random(2, 33)
	local rhs = lhs - 1
	return Ast.SubExpression(Ast.NumberExpression(lhs), Ast.NumberExpression(rhs), false)
end

local function buildLayeredIndirectBase(baseExpression, layers, nonConstantIndex)
	layers = math.max(1, math.floor(layers or 1))
	local current = baseExpression
	for _ = 1, layers, 1 do
		current = Ast.IndexExpression(
			Ast.TableConstructorExpression({
				Ast.TableEntry(current),
			}),
			buildIndexExpression(nonConstantIndex)
		)
	end
	return current
end

local function buildLegacyIndirectBase(baseExpression)
	return Ast.IndexExpression(
		Ast.TableConstructorExpression({
			Ast.TableEntry(baseExpression),
		}),
		Ast.NumberExpression(1)
	)
end

local function isAlreadyIndirect(baseExpression)
	if not baseExpression or baseExpression.kind ~= AstKind.IndexExpression then
		return false
	end
	if baseExpression.index.kind ~= AstKind.NumberExpression or baseExpression.index.value ~= 1 then
		return false
	end
	local base = baseExpression.base
	if not base or base.kind ~= AstKind.TableConstructorExpression then
		return false
	end
	return #base.entries == 1
end

function IndirectFunctionCalls:apply(ast)
	local threshold = self.Threshold
	local includeStatements = self.IncludeStatements
	local includeExpressions = self.IncludeExpressions
	local includePassSelf = self.IncludePassSelf
	local indirectionLayers = self.IndirectionLayers
	local nonConstantIndex = self.NonConstantIndex

	local function applyIndirection(node)
		if node.__indirect_function_calls_applied then
			return node
		end

		if isAlreadyIndirect(node.base) and indirectionLayers == 1 and not nonConstantIndex then
			node.__indirect_function_calls_applied = true
			return node
		end

		if indirectionLayers == 1 and not nonConstantIndex then
			node.base = buildLegacyIndirectBase(node.base)
		else
			node.base = buildLayeredIndirectBase(node.base, indirectionLayers, nonConstantIndex)
		end

		node.__indirect_function_calls_applied = true
		return node
	end

	visitAst(ast, nil, function(node)
		if includeStatements and node.kind == AstKind.FunctionCallStatement and math.random() <= threshold then
			return applyIndirection(node)
		end

		if includeExpressions and node.kind == AstKind.FunctionCallExpression and math.random() <= threshold then
			return applyIndirection(node)
		end

		if includePassSelf and node.kind == AstKind.PassSelfFunctionCallStatement and math.random() <= threshold then
			return applyIndirection(node)
		end

		if includePassSelf and node.kind == AstKind.PassSelfFunctionCallExpression and math.random() <= threshold then
			return applyIndirection(node)
		end

		return node
	end)
end

return IndirectFunctionCalls
