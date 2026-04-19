-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ControlFlowInversion.lua
--
-- This Step transforms code to use unconventional control flow patterns, making it harder to understand
-- through traditional code analysis and decompilation.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local AstKind = Ast.AstKind;

local ControlFlowInversion = setmetatable({
	Name = "ControlFlowInversion";
	Description = "Transforms while-loops into repeat-until loops to obscure code logic";
}, Step);

ControlFlowInversion.__index = ControlFlowInversion;

rawset(ControlFlowInversion, "new", function(self, settings)
	settings = settings or {};
	local step = {
		Name = self.Name;
		Description = self.Description;
		Settings = settings;
		TransformLoops = settings.TransformLoops ~= false;
	};

	setmetatable(step, self);
	return step;
end)

local function transformWhileToRepeat(whileNode)
	if whileNode.kind == AstKind.WhileStatement then
		local negatedCondition = Ast.NotExpression(whileNode.condition);
		return Ast.RepeatStatement(negatedCondition, whileNode.body);
	end

	return whileNode;
end

rawset(ControlFlowInversion, "apply", function(self, ast, pipeline)
	local modifiedCount = 0;

	local function visitNode(node)
		if not node or type(node) ~= "table" then
			return node;
		end

		if self.TransformLoops and node.kind == AstKind.WhileStatement then
			modifiedCount = modifiedCount + 1;
			node = transformWhileToRepeat(node);
		end

		for key, child in pairs(node) do
			if type(child) == "table" and child.kind then
				node[key] = visitNode(child);
			elseif type(child) == "table" and type(child[1]) == "table" and child[1].kind then
				for i, item in ipairs(child) do
					child[i] = visitNode(item);
				end
			end
		end

		return node;
	end

	ast = visitNode(ast);

	require("logger"):info(string.format(
		"ControlFlowInversion: Transformed %d while-loops to repeat-until",
		modifiedCount
	));

	return ast;
end)

return ControlFlowInversion;
