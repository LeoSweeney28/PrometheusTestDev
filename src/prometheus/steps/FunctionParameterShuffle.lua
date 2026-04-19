-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- FunctionParameterShuffle.lua
--
-- This Script provides an Obfuscation Step that shuffles parameter order while preserving behavior.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitAst = require("prometheus.visitast")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local FunctionParameterShuffle = Step:extend()
FunctionParameterShuffle.Description = "Shuffles function parameter order and remaps values in function prologue"
FunctionParameterShuffle.Name = "Function Parameter Shuffle"

FunctionParameterShuffle.SettingsDescriptor = {
	Threshold = {
		type = "number",
		default = 0.2,
		min = 0,
		max = 1,
	},
	MinArgs = {
		type = "number",
		default = 2,
		min = 2,
		max = 32,
	},
	MaxArgs = {
		type = "number",
		default = 8,
		min = 2,
		max = 64,
	},
	PreserveFirstArgument = {
		type = "boolean",
		default = true,
	},
	MaxShuffleAttempts = {
		type = "number",
		default = 6,
		min = 1,
		max = 20,
	},
	SkipMemberFunctionDeclarations = {
		type = "boolean",
		default = true,
	},
}

function FunctionParameterShuffle:init(_) end

local function isFunctionNode(node)
	return node.kind == AstKind.FunctionDeclaration
		or node.kind == AstKind.LocalFunctionDeclaration
		or node.kind == AstKind.FunctionLiteralExpression
end

local function isIdentityPermutation(original, shuffled)
	for i = 1, #original, 1 do
		if original[i] ~= shuffled[i] then
			return false
		end
	end
	return true
end

function FunctionParameterShuffle:apply(ast)
	local threshold = self.Threshold
	local minArgs = math.floor(self.MinArgs)
	local maxArgs = math.floor(self.MaxArgs)
	local preserveFirstArgument = self.PreserveFirstArgument
	local maxShuffleAttempts = math.floor(self.MaxShuffleAttempts)
	local skipMemberFunctionDeclarations = self.SkipMemberFunctionDeclarations
	if maxArgs < minArgs then
		maxArgs = minArgs
	end
	if maxShuffleAttempts < 1 then
		maxShuffleAttempts = 1
	end

	visitAst(ast, nil, function(node)
		if not isFunctionNode(node) then
			return node
		end
		if node.__function_parameter_shuffle_applied then
			return node
		end
		if skipMemberFunctionDeclarations and node.kind == AstKind.FunctionDeclaration and node.indices and #node.indices > 0 then
			return node
		end
		if math.random() > threshold then
			return node
		end

		local args = node.args or {}
		local argCount = #args
		if argCount < minArgs or argCount > maxArgs then
			return node
		end
		if preserveFirstArgument and argCount < 3 then
			return node
		end

		for _, argId in ipairs(args) do
			if type(argId) ~= "number" then
				return node
			end
		end

		local originalArgs = {}
		for i = 1, argCount, 1 do
			originalArgs[i] = args[i]
		end

		local shuffledArgs = {}
		for i = 1, argCount, 1 do
			shuffledArgs[i] = args[i]
		end

		local success = false
		for _ = 1, maxShuffleAttempts, 1 do
			for i = 1, argCount, 1 do
				shuffledArgs[i] = originalArgs[i]
			end

			if preserveFirstArgument then
				local tail = {}
				for i = 2, argCount, 1 do
					tail[#tail + 1] = shuffledArgs[i]
				end
				util.shuffle(tail)
				for i = 2, argCount, 1 do
					shuffledArgs[i] = tail[i - 1]
				end
			else
				util.shuffle(shuffledArgs)
			end

			if not isIdentityPermutation(originalArgs, shuffledArgs) then
				success = true
				break
			end
		end

		if not success then
			return node
		end

		node.args = shuffledArgs

		local funcScope = node.body and node.body.scope
		if not funcScope then
			return node
		end
		if type(node.body.statements) ~= "table" then
			return node
		end

		local tempIds = {}
		local tempExpressions = {}
		local tempByArgId = {}

		for i = 1, argCount, 1 do
			local argId = shuffledArgs[i]
			local tempId = funcScope:addVariable()
			tempIds[i] = tempId
			tempByArgId[argId] = tempId
			tempExpressions[i] = Ast.VariableExpression(funcScope, argId)
		end

		local lhs = {}
		local rhs = {}
		for i = 1, argCount, 1 do
			local originalArgId = originalArgs[i]
			local valueHolderArgId = shuffledArgs[i]
			lhs[i] = Ast.AssignmentVariable(funcScope, originalArgId)
			rhs[i] = Ast.VariableExpression(funcScope, tempByArgId[valueHolderArgId])
		end

		local prologueDecl = Ast.LocalVariableDeclaration(funcScope, tempIds, tempExpressions)
		local prologueAssign = Ast.AssignmentStatement(lhs, rhs)

		table.insert(node.body.statements, 1, prologueAssign)
		table.insert(node.body.statements, 1, prologueDecl)
		node.__function_parameter_shuffle_applied = true

		return node
	end)
end

return FunctionParameterShuffle
