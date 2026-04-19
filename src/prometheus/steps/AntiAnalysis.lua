-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- AntiAnalysisObfuscation.lua
--
-- This Step injects anti-analysis code patterns to confuse static analysis and decompilers.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local AstKind = Ast.AstKind;
local AntiAnalysis = require("prometheus.antianalysis");

local AntiAnalysisObfuscation = setmetatable({
	Name = "AntiAnalysis";
	Description = "Injects anti-analysis patterns to defeat decompilers and static analyzers";
}, Step);

AntiAnalysisObfuscation.__index = AntiAnalysisObfuscation;

rawset(AntiAnalysisObfuscation, "new", function(self, settings)
	settings = settings or {};
	local step = {
		Name = self.Name;
		Description = self.Description;
		Settings = settings;
		InjectionPoints = settings.InjectionPoints or "global"; -- "global", "function", "block"
		FakeDataFlow = settings.FakeDataFlow ~= false; -- Default true
		MaskedConditionals = settings.MaskedConditionals ~= false; -- Default true
		DebugChecks = settings.DebugChecks ~= false; -- Default true
		DecoyVariables = settings.DecoyVariables or 2;
	};
	
	setmetatable(step, self);
	return step;
end)

rawset(AntiAnalysisObfuscation, "apply", function(self, ast, pipeline)
	local modifiedCount = 0;
	local scope = ast.globalScope;
	local visitCounter = 0;
	
	-- Inject anti-analysis patterns at various points
	local function visitNode(node, parent, isRoot)
		if not node or type(node) ~= "table" then
			return node;
		end
		visitCounter = visitCounter + 1;
		
		-- Inject at global level
		if isRoot and node.kind == AstKind.Block then
			local injectedStatements = {};
			
			-- Add fake debug checks
			if self.DebugChecks then
				table.insert(injectedStatements, AntiAnalysis.createDebugCheck());
				modifiedCount = modifiedCount + 1;
			end
			
			-- Add fake version checks
			if math.random() > 0.5 then
				table.insert(injectedStatements, AntiAnalysis.createFakeVersionCheck());
				modifiedCount = modifiedCount + 1;
			end
			
			-- Add fake external dependencies
			for _, stmt in ipairs(AntiAnalysis.createFakeExternalDependency()) do
				table.insert(injectedStatements, stmt);
				modifiedCount = modifiedCount + 1;
			end
			
			-- Add original statements
			if node.statements then
				for _, stmt in ipairs(node.statements) do
					table.insert(injectedStatements, stmt);
				end
			end
			
			node.statements = injectedStatements;
		end
		
		-- Inject fake data flow patterns
		if self.FakeDataFlow and node.kind == AstKind.Block and not isRoot and (visitCounter % 2 == 0) then
			for _, stmt in ipairs(AntiAnalysis.createFakeDataFlow()) do
				table.insert(node.statements or {}, stmt);
				modifiedCount = modifiedCount + 1;
			end
		end
		
		-- Wrap conditions in masked patterns
		if self.MaskedConditionals and node.kind == AstKind.IfStatement and (visitCounter % 3 == 0) then
			local realCode = node.trueStatement;
			node = AntiAnalysis.createMaskedConditional(realCode);
			modifiedCount = modifiedCount + 1;
		end
		
		-- Add decoy variables
		if self.DecoyVariables > 0 and node.kind == AstKind.Block then
			local decoyCount = 0;
			for i = 1, math.min(self.DecoyVariables, 3) do
				if ((visitCounter + i) % 2) == 0 then
					local decoy = AntiAnalysis.createDecoyVariable(scope);
					table.insert(node.statements or {}, decoy.declaration);
					decoyCount = decoyCount + 1;
				end
			end
			if decoyCount > 0 then
				modifiedCount = modifiedCount + decoyCount;
			end
		end
		
		-- Recursively visit children
		for key, child in pairs(node) do
			if type(child) == "table" and child.kind then
				node[key] = visitNode(child, node, false);
			elseif type(child) == "table" and type(child[1]) == "table" and child[1].kind then
				for i, item in ipairs(child) do
					child[i] = visitNode(item, node, false);
				end
			end
		end
		
		return node;
	end
	
	ast = visitNode(ast, nil, true);
	
	require("logger"):info(string.format(
		"AntiAnalysis: Injected %d anti-analysis patterns",
		modifiedCount
	));
	
	return ast;
end)

return AntiAnalysisObfuscation;
