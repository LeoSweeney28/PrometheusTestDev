-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- OpaquePredicates.lua
--
-- This Script provides an Obfuscation Step that wraps statements in opaque predicates.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitAst = require("prometheus.visitast")

local AstKind = Ast.AstKind

local OpaquePredicates = Step:extend()
OpaquePredicates.Description = "Wraps selected statements in opaque predicates"
OpaquePredicates.Name = "Opaque Predicates"

OpaquePredicates.SettingsDescriptor = {
	Threshold = {
		type = "number",
		default = 0.35,
		min = 0,
		max = 1,
	},
	NestingDepth = {
		type = "number",
		default = 1,
		min = 1,
		max = 3,
	},
	IncludeElseNoise = {
		type = "boolean",
		default = true,
	},
	WrapControlFlow = {
		type = "boolean",
		default = false,
	},
	PredicateComplexity = {
		type = "number",
		default = 2,
		min = 1,
		max = 3,
	},
}

local function generateSimpleTruePredicate()
	local variant = math.random(1, 5)
	if variant == 1 then
		local a = math.random(100, 5000)
		local b = math.random(1, 31)
		return Ast.EqualsExpression(
			Ast.SubExpression(Ast.NumberExpression(a + b), Ast.NumberExpression(b), false),
			Ast.NumberExpression(a),
			false
		)
	elseif variant == 2 then
		local a = math.random(3, 97)
		local b = math.random(2, 17)
		return Ast.LessThanOrEqualsExpression(
			Ast.ModExpression(Ast.NumberExpression(a * b + a), Ast.NumberExpression(a), false),
			Ast.NumberExpression(0),
			false
		)
	elseif variant == 3 then
		local a = math.random(10, 500)
		return Ast.NotExpression(
			Ast.NotEqualsExpression(Ast.NumberExpression(a), Ast.NumberExpression(a), false),
			false
		)
	elseif variant == 4 then
		local a = math.random(2, 64)
		return Ast.GreaterThanExpression(
			Ast.AddExpression(Ast.NumberExpression(a), Ast.NumberExpression(1), false),
			Ast.NumberExpression(a),
			false
		)
	end

	local a = math.random(2, 50)
	local b = math.random(2, 50)
	local c = a * b
	return Ast.EqualsExpression(
		Ast.MulExpression(Ast.NumberExpression(a), Ast.NumberExpression(b), false),
		Ast.NumberExpression(c),
		false
	)
end

local function generateTruePredicate(complexity)
	local base = generateSimpleTruePredicate()
	if complexity <= 1 then
		return base
	end

	if complexity == 2 then
		if math.random() < 0.5 then
			return Ast.AndExpression(base, generateSimpleTruePredicate(), false)
		end
		return Ast.NotExpression(Ast.NotExpression(base, false), false)
	end

	if math.random() < 0.5 then
		return Ast.OrExpression(
			base,
			Ast.EqualsExpression(Ast.NumberExpression(1), Ast.NumberExpression(2), false),
			false
		)
	end

	return Ast.AndExpression(
		Ast.NotExpression(Ast.NotExpression(base, false), false),
		generateSimpleTruePredicate(),
		false
	)
end

local function isWrappableStatement(statement, wrapControlFlow)
	local kind = statement.kind
	if kind == AstKind.LocalVariableDeclaration or kind == AstKind.LocalFunctionDeclaration or kind == AstKind.FunctionDeclaration then
		return false
	end
	if not wrapControlFlow then
		if kind == AstKind.ReturnStatement
			or kind == AstKind.IfStatement
			or kind == AstKind.WhileStatement
			or kind == AstKind.RepeatStatement
			or kind == AstKind.ForStatement
			or kind == AstKind.ForInStatement
			or kind == AstKind.BreakStatement
			or kind == AstKind.ContinueStatement then
			return false
		end
	end
	return kind == AstKind.FunctionCallStatement
		or kind == AstKind.PassSelfFunctionCallStatement
		or kind == AstKind.AssignmentStatement
		or kind == AstKind.ReturnStatement
		or kind == AstKind.IfStatement
		or kind == AstKind.WhileStatement
		or kind == AstKind.RepeatStatement
		or kind == AstKind.ForStatement
		or kind == AstKind.ForInStatement
		or kind == AstKind.DoStatement
		or kind == AstKind.BreakStatement
		or kind == AstKind.ContinueStatement
		or kind == AstKind.CompoundAddStatement
		or kind == AstKind.CompoundSubStatement
		or kind == AstKind.CompoundMulStatement
		or kind == AstKind.CompoundDivStatement
		or kind == AstKind.CompoundModStatement
		or kind == AstKind.CompoundPowStatement
		or kind == AstKind.CompoundConcatStatement
end

function OpaquePredicates:init(_) end

function OpaquePredicates:apply(ast)
	local threshold = self.Threshold
	local depth = math.floor(self.NestingDepth)
	local includeElseNoise = self.IncludeElseNoise
	local wrapControlFlow = self.WrapControlFlow
	local predicateComplexity = math.floor(self.PredicateComplexity)

	visitAst(ast, nil, function(node, data)
		if not node.isStatement then
			return node
		end
		if not isWrappableStatement(node, wrapControlFlow) then
			return node
		end
		if math.random() > threshold then
			return node
		end

		local current = node
		for _ = 1, depth, 1 do
			local parentScope = data.scope
			local bodyScope = Scope:new(parentScope)
			local bodyBlock = Ast.Block({current}, bodyScope)
			local elseBody = nil
			if includeElseNoise and math.random() < 0.35 then
				local noiseScope = Scope:new(parentScope)
				elseBody = Ast.Block({
					Ast.DoStatement(Ast.Block({
						Ast.NopStatement(),
					}, Scope:new(noiseScope))),
				}, noiseScope)
			end
			current = Ast.IfStatement(generateTruePredicate(predicateComplexity), bodyBlock, {}, elseBody)
		end

		return current
	end)
end

return OpaquePredicates
