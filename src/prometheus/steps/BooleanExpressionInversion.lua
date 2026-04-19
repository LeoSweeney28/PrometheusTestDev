-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- BooleanExpressionInversion.lua
--
-- This Script provides an Obfuscation Step that inverts boolean expressions.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitAst = require("prometheus.visitast")

local AstKind = Ast.AstKind

local BooleanExpressionInversion = Step:extend()
BooleanExpressionInversion.Description = "Inverts boolean and comparison expressions"
BooleanExpressionInversion.Name = "Boolean Expression Inversion"

BooleanExpressionInversion.SettingsDescriptor = {
	Threshold = {
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	InvertLiterals = {
		type = "boolean",
		default = true,
	},
	InvertComparisons = {
		type = "boolean",
		default = true,
	},
	InvertLogicExpressions = {
		type = "boolean",
		default = true,
	},
}

local inverseComparisonFactory = {
	[AstKind.EqualsExpression] = Ast.NotEqualsExpression,
	[AstKind.NotEqualsExpression] = Ast.EqualsExpression,
	[AstKind.LessThanExpression] = Ast.GreaterThanOrEqualsExpression,
	[AstKind.GreaterThanExpression] = Ast.LessThanOrEqualsExpression,
	[AstKind.LessThanOrEqualsExpression] = Ast.GreaterThanExpression,
	[AstKind.GreaterThanOrEqualsExpression] = Ast.LessThanExpression,
}

function BooleanExpressionInversion:init(_) end

function BooleanExpressionInversion:apply(ast)
	local threshold = self.Threshold
	local invertLiterals = self.InvertLiterals
	local invertComparisons = self.InvertComparisons
	local invertLogicExpressions = self.InvertLogicExpressions

	visitAst(ast, nil, function(node)
		if not node.isExpression then
			return node
		end
		if math.random() > threshold then
			return node
		end

		if invertLiterals and node.kind == AstKind.BooleanExpression then
			return Ast.NotExpression(Ast.BooleanExpression(not node.value), false)
		end

		if invertComparisons then
			local inverseFactory = inverseComparisonFactory[node.kind]
			if inverseFactory then
				return Ast.NotExpression(inverseFactory(node.lhs, node.rhs, false), false)
			end
		end

		if invertLogicExpressions then
			if node.kind == AstKind.AndExpression then
				return Ast.NotExpression(
					Ast.OrExpression(
						Ast.NotExpression(node.lhs, false),
						Ast.NotExpression(node.rhs, false),
						false
					),
					false
				)
			end

			if node.kind == AstKind.OrExpression then
				return Ast.NotExpression(
					Ast.AndExpression(
						Ast.NotExpression(node.lhs, false),
						Ast.NotExpression(node.rhs, false),
						false
					),
					false
				)
			end
		end

		return node
	end)
end

return BooleanExpressionInversion
