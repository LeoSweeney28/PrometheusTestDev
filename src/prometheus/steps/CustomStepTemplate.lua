-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- CustomStepTemplate.lua
--
-- This is a template for creating custom obfuscation steps.
-- Copy this file and modify to create your own step.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local StepUtils = require("prometheus.StepUtils");
local AstBuilder = require("prometheus.AstBuilder");
local visitAst = require("prometheus.visitast");

-- Create your custom step by extending the base Step
local MyCustomStep = Step:extend();
MyCustomStep.Description = "My custom obfuscation step";
MyCustomStep.Name = "My Custom Step";

-- Define settings that users can configure
MyCustomStep.SettingsDescriptor = {
	Threshold = {
		type = "number";
		default = 0.5;
		min = 0;
		max = 1;
	};
	CustomOption = {
		type = "boolean";
		default = true;
	};
};

-- Initialize the step (called when the step is instantiated)
function MyCustomStep:init(settings)
	-- The base Step class will automatically apply settings from the descriptor
	-- You can add custom initialization here if needed
end

-- Apply the step to the AST
function MyCustomStep:apply(ast)
	-- Your transformation logic here
	-- Use visitAst to traverse and modify the AST
	
	local threshold = self.Threshold;
	local customOption = self.CustomOption;
	
	visitAst(ast, nil, function(node, data)
		-- Return the original node if threshold check fails
		if not StepUtils:passThreshold(threshold) then
			return node;
		end
		
		-- Only process expressions in this example
		if not node.isExpression then
			return node;
		end
		
		-- Add your transformation logic
		-- Example: wrap expressions in additional operations
		
		if customOption then
			-- Custom transformation
		end
		
		return node;
	end);
end

return MyCustomStep;

--[[
HOW TO USE THIS TEMPLATE:

1. Copy this file to src/prometheus/steps/MyStep.lua

2. Customize the Name, Description, SettingsDescriptor, and apply() method

3. Register your step with the StepRegistry:
   local Prometheus = require("prometheus");
   local MyStep = require("prometheus.steps.MyStep");
   Prometheus.StepRegistry:register("MyStep", MyStep, {
       name = "My Custom Step";
       description = "Does something cool";
       author = "Your Name";
       version = "1.0";
   });

4. Use in a config:
   {
       Steps = {
           {Name = "MyStep", Settings = {Threshold = 0.7, CustomOption = true}};
       }
   }

USEFUL HELPER FUNCTIONS:

- StepUtils:passThreshold(threshold) - Check if should apply
- StepUtils:randomChoice(choices) - Pick random option
- StepUtils:shuffle(tbl) - Shuffle table
- StepUtils:contains(tbl, value) - Check membership
- AstBuilder:truePredicate() - Generate true-valued boolean expression
- AstBuilder:binaryOp(kind, lhs, rhs) - Build binary operations
- AstBuilder:comparison(kind, lhs, rhs) - Build comparisons
- visitAst(ast, previsit, postvisit) - Traverse AST

EXAMPLE STEP PATTERNS:

Pattern 1: Transform all nodes of a type
   visitAst(ast, nil, function(node)
       if node.kind == AstKind.NumberExpression then
           return Ast.AddExpression(node, Ast.NumberExpression(0));
       end
       return node;
   end);

Pattern 2: Wrap statements conditionally
   visitAst(ast, nil, function(node, data)
       if node.isStatement and StepUtils:passThreshold(threshold) then
           return Ast.DoStatement(Ast.Block({node}, data.scope));
       end
       return node;
   end);

Pattern 3: Traverse with pre/post processing
   visitAst(ast, 
       function(node, data) -- previsit
           -- Called before children are visited
           return node;
       end,
       function(node, data) -- postvisit
           -- Called after children are visited
           return node;
       end
   );
--]]
