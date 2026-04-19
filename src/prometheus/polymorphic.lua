-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- polymorphic.lua
--
-- This Script provides polymorphic code generation - multiple semantically equivalent implementations
-- that vary each time they're generated. This defeats static analysis and pattern recognition.

local logger = require("logger");
local Ast = require("prometheus.ast");
local AstKind = Ast.AstKind;

local Polymorphic = {};

-- Generate multiple equivalent implementations of a value
function Polymorphic.generateValueForms(value)
	-- For a number, generate different computation paths that yield same result
	if type(value) == "number" then
		local forms = {
			-- Direct value
			function() return Ast.NumberExpression(value); end,
			-- Via addition
			function() return Ast.AddExpression(Ast.NumberExpression(value), Ast.NumberExpression(0)); end,
			-- Via subtraction
			function() return Ast.SubExpression(Ast.NumberExpression(value + 5), Ast.NumberExpression(5)); end,
			-- Via multiplication
			function() return Ast.MulExpression(Ast.NumberExpression(value), Ast.NumberExpression(1)); end,
		};
		
		if value ~= 0 then
			table.insert(forms, function() 
				return Ast.DivExpression(Ast.NumberExpression(value * 2), Ast.NumberExpression(2)); 
			end);
		end
		
		-- Select random form
		return forms[math.random(1, #forms)]();
	end
	
	if type(value) == "string" then
		local forms = {
			-- Direct string
			function() return Ast.StringExpression(value); end,
			-- Via table concatenation
			function()
				local parts = {};
				for i = 1, #value do
					table.insert(parts, Ast.StringExpression(value:sub(i, i)));
				end
				local result = parts[1];
				for i = 2, #parts do
					result = Ast.ConcatenationExpression(result, parts[i]);
				end
				return result;
			end,
		};
		
		return forms[math.random(1, #forms)]();
	end
	
	if type(value) == "boolean" then
		local forms = {
			-- Direct boolean
			function() return Ast.BooleanExpression(value); end,
			-- Via comparison
			function()
				if value then
					return Ast.EqualsComparison(Ast.NumberExpression(1), Ast.NumberExpression(1));
				else
					return Ast.EqualsComparison(Ast.NumberExpression(1), Ast.NumberExpression(2));
				end
			end,
		};
		
		return forms[math.random(1, #forms)]();
	end
	
	return Ast.NilExpression();
end

-- Generate equivalent conditional branches
function Polymorphic.generateConditionalForms(condition, trueBlock, falseBlock)
	local forms = {
		-- Direct if statement
		function()
			return Ast.IfStatement(condition, trueBlock, falseBlock);
		end,
		-- Inverted with swapped branches
		function()
			local notCond = Ast.NotExpression(condition);
			return Ast.IfStatement(notCond, falseBlock, trueBlock);
		end,
		-- Ternary-like with and/or operators
		function()
			local condExpr = Ast.AndExpression(condition, trueBlock);
			return Ast.OrExpression(condExpr, falseBlock);
		end,
	};
	
	return forms[math.random(1, #forms)]();
end

-- Generate equivalent loop structures
function Polymorphic.generateLoopForms(loopVar, maxIter, body)
	local forms = {
		-- Forward counting
		function()
			return Ast.ForStatement(loopVar, Ast.NumberExpression(1), Ast.NumberExpression(maxIter), nil, body);
		end,
		-- Backward counting with negated comparison
		function()
			return Ast.ForStatement(loopVar, Ast.NumberExpression(maxIter), Ast.NumberExpression(1), 
				Ast.NumberExpression(-1), body);
		end,
		-- While loop alternative
		function()
			local counter = Ast.VariableExpression(nil, loopVar);
			return Ast.WhileStatement(
				Ast.LessThanComparison(counter, Ast.NumberExpression(maxIter)),
				body
			);
		end,
	};
	
	return forms[math.random(1, #forms)]();
end

-- Generate polymorphic function signatures (same logic, different structure)
function Polymorphic.generateFunctionForms(funcName, args, body)
	local forms = {
		-- Standard function
		function()
			return Ast.FunctionDefinition(funcName, args, body);
		end,
		-- With extra scoping
		function()
			local wrappedBody = {
				Ast.LocalVariableDeclaration("_scope", Ast.TableConstructor({})),
				unpack(body),
			};
			return Ast.FunctionDefinition(funcName, args, wrappedBody);
		end,
	};
	
	return forms[math.random(1, #forms)]();
end

-- Create obfuscated wrapper that returns different implementations each call
function Polymorphic.createPolymorphicWrapper(value, varName)
	-- Generate a table of equivalent forms
	local implementations = {
		Polymorphic.generateValueForms(value),
		Polymorphic.generateValueForms(value),
		Polymorphic.generateValueForms(value),
	};
	
	-- Return random implementation
	return Ast.IndexExpression(
		Ast.TableConstructor(implementations),
		Ast.NumberExpression(math.random(1, #implementations))
	);
end

-- Polymorphic switch-like structure instead of if-elseif chains
function Polymorphic.createPolymorphicSwitch(value, cases)
	-- Generate as table dispatch instead of if-elseif
	local caseTable = {};
	for caseVal, caseBody in pairs(cases) do
		table.insert(caseTable, { key = Ast.NumberExpression(caseVal), value = caseBody });
	end
	
	local tableExpr = Ast.TableConstructor(caseTable);
	local handler = Ast.IndexExpression(tableExpr, value);
	
	return Ast.FunctionCallExpression(handler, {});
end

return Polymorphic;
