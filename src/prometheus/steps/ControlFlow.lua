-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ControlFlow.lua
--
-- This Script provides an Obfuscation Step that adds extra control-flow wrappers.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitAst = require("prometheus.visitast")

local AstKind = Ast.AstKind

local ControlFlow = Step:extend()
ControlFlow.Description = "Wraps selected statements in additional control-flow blocks"
ControlFlow.Name = "Control Flow"

ControlFlow.SettingsDescriptor = {
	Threshold = {
		type = "number",
		default = 0.3,
		min = 0,
		max = 1,
	},
	MaxWrappers = {
		type = "number",
		default = 1,
		min = 1,
		max = 3,
	},
	IncludeFalseBranchNoise = {
		type = "boolean",
		default = true,
	},
	WrapInDoBlock = {
		type = "boolean",
		default = true,
	},
	WrapControlStatements = {
		type = "boolean",
		default = false,
	},
}

local function createTruePredicate()
	local variant = math.random(1, 4)
	if variant == 1 then
		local a = math.random(2, 128)
		return Ast.EqualsExpression(
			Ast.SubExpression(Ast.NumberExpression(a + 1), Ast.NumberExpression(1), false),
			Ast.NumberExpression(a),
			false
		)
	elseif variant == 2 then
		local a = math.random(2, 32)
		return Ast.GreaterThanExpression(
			Ast.AddExpression(Ast.NumberExpression(a), Ast.NumberExpression(1), false),
			Ast.NumberExpression(a),
			false
		)
	elseif variant == 3 then
		local a = math.random(3, 97)
		return Ast.EqualsExpression(
			Ast.ModExpression(Ast.NumberExpression(a * 3), Ast.NumberExpression(a), false),
			Ast.NumberExpression(0),
			false
		)
	end

	local a = math.random(4, 64)
	return Ast.NotExpression(
		Ast.NotEqualsExpression(Ast.NumberExpression(a), Ast.NumberExpression(a), false),
		false
	)
end

local function createNoiseBlock(parentScope)
	local noiseScope = Scope:new(parentScope)
	local body = {
		Ast.DoStatement(Ast.Block({
			Ast.NopStatement(),
		}, Scope:new(noiseScope))),
	}
	return Ast.Block(body, noiseScope)
end

local function isWrappableStatement(statement, wrapControlStatements)
	local kind = statement.kind
	if kind == AstKind.LocalVariableDeclaration
		or kind == AstKind.LocalFunctionDeclaration
		or kind == AstKind.FunctionDeclaration then
		return false
	end

	if not wrapControlStatements then
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
		or kind == AstKind.DoStatement
		or kind == AstKind.CompoundAddStatement
		or kind == AstKind.CompoundSubStatement
		or kind == AstKind.CompoundMulStatement
		or kind == AstKind.CompoundDivStatement
		or kind == AstKind.CompoundModStatement
		or kind == AstKind.CompoundPowStatement
		or kind == AstKind.CompoundConcatStatement
		or kind == AstKind.ReturnStatement
		or kind == AstKind.IfStatement
		or kind == AstKind.WhileStatement
		or kind == AstKind.RepeatStatement
		or kind == AstKind.ForStatement
		or kind == AstKind.ForInStatement
		or kind == AstKind.BreakStatement
		or kind == AstKind.ContinueStatement
end

local function wrapStatement(statement, parentScope, includeFalseBranchNoise, wrapInDoBlock)
	local trueBlock = Ast.Block({statement}, Scope:new(parentScope))
	local elseBlock = nil
	if includeFalseBranchNoise and math.random() < 0.4 then
		elseBlock = createNoiseBlock(parentScope)
	end

	local wrapped = Ast.IfStatement(createTruePredicate(), trueBlock, {}, elseBlock)
	if wrapInDoBlock then
		wrapped = Ast.DoStatement(Ast.Block({wrapped}, Scope:new(parentScope)))
	end
	return wrapped
end

function ControlFlow:init(_) end

function ControlFlow:apply(ast)
	local threshold = self.Threshold
	local maxWrappers = math.max(1, math.floor(self.MaxWrappers))
	local includeFalseBranchNoise = self.IncludeFalseBranchNoise
	local wrapInDoBlock = self.WrapInDoBlock
	local wrapControlStatements = self.WrapControlStatements

	visitAst(ast, nil, function(node, data)
		if not node.isStatement then
			return node
		end
		if not isWrappableStatement(node, wrapControlStatements) then
			return node
		end
		if math.random() > threshold then
			return node
		end

		local wrapped = node
		local wraps = math.random(1, maxWrappers)
		for _ = 1, wraps, 1 do
			wrapped = wrapStatement(wrapped, data.scope, includeFalseBranchNoise, wrapInDoBlock)
		end
		return wrapped
	end)
end

return ControlFlow
