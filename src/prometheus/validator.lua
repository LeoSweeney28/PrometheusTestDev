-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- validator.lua
--
-- This Script provides AST and semantic validation to catch bugs before compilation.

local Ast = require("prometheus.ast");
local util = require("prometheus.util");
local visitAst = require("prometheus.visitast");

local AstKind = Ast.AstKind;
local Validator = {};

function Validator:new()
	local instance = {
		errors = {};
		warnings = {};
	};
	setmetatable(instance, self);
	self.__index = self;
	return instance;
end

function Validator:addError(message, context)
	table.insert(self.errors, {
		message = message;
		context = context or "unknown";
		level = "error";
	});
end

function Validator:addWarning(message, context)
	table.insert(self.warnings, {
		message = message;
		context = context or "unknown";
		level = "warning";
	});
end

function Validator:validate(ast)
	self.errors = {};
	self.warnings = {};

	if not ast or not ast.kind then
		self:addError("Invalid AST: missing kind property");
		return self.errors, self.warnings;
	end

	if ast.kind ~= AstKind.TopNode then
		self:addError("Invalid root AST: expected TopNode, got " .. tostring(ast.kind));
		return self.errors, self.warnings;
	end

	if not ast.body or not ast.body.statements then
		self:addError("Invalid AST: TopNode missing body.statements");
		return self.errors, self.warnings;
	end

	visitAst(ast, function(node, data)
		self:validateNode(node, data);
	end);

	return self.errors, self.warnings;
end

function Validator:validateNode(node, data)
	if not node then
		self:addError("Null node encountered during validation");
		return;
	end

	local kind = node.kind;

	-- Validate binary operations have proper operands
	if kind == AstKind.AddExpression
		or kind == AstKind.SubExpression
		or kind == AstKind.MulExpression
		or kind == AstKind.DivExpression
		or kind == AstKind.ModExpression
		or kind == AstKind.PowExpression then
		if not node.lhs or not node.rhs then
			self:addError("Binary operation missing operands: " .. tostring(kind));
		end
	end

	-- Validate comparison operations
	if kind == AstKind.EqualsExpression
		or kind == AstKind.NotEqualsExpression
		or kind == AstKind.LessThanExpression
		or kind == AstKind.GreaterThanExpression
		or kind == AstKind.LessThanOrEqualsExpression
		or kind == AstKind.GreaterThanOrEqualsExpression then
		if not node.lhs or not node.rhs then
			self:addError("Comparison operation missing operands: " .. tostring(kind));
		end
	end

	-- Validate logical operations
	if kind == AstKind.AndExpression or kind == AstKind.OrExpression then
		if not node.lhs or not node.rhs then
			self:addError("Logical operation missing operands: " .. tostring(kind));
		end
	end

	-- Validate unary operations
	if kind == AstKind.NotExpression
		or kind == AstKind.NegateExpression
		or kind == AstKind.LenExpression then
		if not node.rhs then
			self:addError("Unary operation missing operand: " .. tostring(kind));
		end
	end

	-- Validate function literals have proper structure
	if kind == AstKind.FunctionLiteralExpression then
		if not node.body or not node.args then
			self:addError("Function literal missing body or args");
		end
	end

	-- Validate assignments have LHS and RHS
	if kind == AstKind.AssignmentStatement then
		if not node.lhs or #node.lhs == 0 then
			self:addError("Assignment statement missing LHS targets");
		end
		if not node.rhs or #node.rhs == 0 then
			self:addError("Assignment statement missing RHS values");
		end
	end

	-- Validate if statements have condition and body
	if kind == AstKind.IfStatement then
		if not node.condition then
			self:addError("If statement missing condition");
		end
		if not node.body then
			self:addError("If statement missing body");
		end
	end

	-- Validate loops have proper structure
	if kind == AstKind.WhileStatement then
		if not node.condition then
			self:addError("While loop missing condition");
		end
		if not node.body then
			self:addError("While loop missing body");
		end
	end

	if kind == AstKind.RepeatStatement then
		if not node.condition then
			self:addError("Repeat loop missing condition");
		end
		if not node.body then
			self:addError("Repeat loop missing body");
		end
	end

	if kind == AstKind.ForStatement then
		if not node.initialValue or not node.finalValue or not node.incrementBy then
			self:addError("For loop missing required expressions");
		end
		if not node.body then
			self:addError("For loop missing body");
		end
	end

	if kind == AstKind.ForInStatement then
		if not node.expressions or #node.expressions == 0 then
			self:addError("ForIn loop missing iterator expressions");
		end
		if not node.body then
			self:addError("ForIn loop missing body");
		end
	end
end

return Validator;
