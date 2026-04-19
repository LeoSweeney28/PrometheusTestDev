-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ExpressionComplexity.lua
--
-- This Step wraps expressions in complex-looking but semantically equivalent computations
-- to make decompilation and analysis more difficult.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local AstKind = Ast.AstKind;
local VisitAst = require("prometheus.visitast");
local Complexity = require("prometheus.complexity");

local ExpressionComplexity = setmetatable({
	Name = "ExpressionComplexity";
	Description = "Wraps expressions in complex-looking but semantically equivalent forms";
}, Step);

ExpressionComplexity.__index = ExpressionComplexity;

rawset(ExpressionComplexity, "new", function(self, settings)
	settings = settings or {};
	local step = {
		Name = self.Name;
		Description = self.Description;
		Settings = settings;
		ComplexityLevel = settings.ComplexityLevel or 2; -- 1=light, 2=medium, 3=heavy
		JunkCodeCount = settings.JunkCodeCount or 1;
		InjectJunk = settings.InjectJunk ~= false; -- Default true
		MaxTransforms = settings.MaxTransforms or 200;
	};
	
	setmetatable(step, self);
	return step;
end)

rawset(ExpressionComplexity, "apply", function(self, ast, pipeline)
	local step = self;
	local modifiedCount = 0;
	local maxTransforms = self.MaxTransforms;
	local visitDepthLimit = 64;
	
	-- Visitor to complexify expressions
	local function visitNode(node, depth)
		if modifiedCount >= maxTransforms then
			return node;
		end

		depth = depth or 0;
		if depth > visitDepthLimit then
			return node;
		end

		if not node or type(node) ~= "table" then
			return node;
		end
		
		-- Complexify numeric expressions
		if node.kind == AstKind.NumberExpression and modifiedCount < maxTransforms then
			modifiedCount = modifiedCount + 1;
			for i = 1, step.ComplexityLevel do
				node = Complexity.complexifyNumber(node);
				if modifiedCount >= maxTransforms then
					break;
				end
			end
			return node;
		end
		
		-- Complexify string expressions
		if node.kind == AstKind.StringExpression and modifiedCount < maxTransforms then
			modifiedCount = modifiedCount + 1;
			for i = 1, step.ComplexityLevel do
				node = Complexity.complexifyString(node);
				if modifiedCount >= maxTransforms then
					break;
				end
			end
			return node;
		end
		
		-- Complexify boolean conditions
		if node.kind == AstKind.IfStatement and modifiedCount < maxTransforms then
			modifiedCount = modifiedCount + 1;
			node.condition = Complexity.complexifyCondition(node.condition);
		end
		
		-- Recursively visit child nodes
		for key, child in pairs(node) do
			if modifiedCount >= maxTransforms then
				break;
			end
			if type(child) == "table" then
				if child.kind then
					node[key] = visitNode(child, depth + 1);
				elseif type(child[1]) == "table" and child[1].kind then
					for i, item in ipairs(child) do
						child[i] = visitNode(item, depth + 1);
						if modifiedCount >= maxTransforms then
							break;
						end
					end
				end
			end
		end
		
		return node;
	end
	
	-- Apply complexification
	ast = visitNode(ast);
	
	require("logger"):info(string.format(
		"ExpressionComplexity: Modified %d expressions (Level %d, Budget %d)",
		modifiedCount, step.ComplexityLevel, maxTransforms
	));
	
	return ast;
end)

return ExpressionComplexity;
