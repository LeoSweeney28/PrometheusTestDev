-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- binary.lua
--
-- This Script contains the expression handler for the Binary operations (Add, Sub, Mul, Div, etc.).
-- Now includes type guards to prevent boolean-arithmetic and similar runtime errors.

local Ast = require("prometheus.ast");
local AstKind = Ast.AstKind;

local NUMERIC_ARITHMETIC_OPS = {
	[AstKind.AddExpression] = true;
	[AstKind.SubExpression] = true;
	[AstKind.MulExpression] = true;
	[AstKind.DivExpression] = true;
	[AstKind.ModExpression] = true;
	[AstKind.PowExpression] = true;
};

local function createTypeGuardedArithmetic(self, scope, lhsVar, rhsVar, kind)
    local envExpr = self:env(scope);
    local typeExpr = Ast.IndexExpression(envExpr, Ast.StringExpression("type"));
    local tonumberExpr = Ast.IndexExpression(envExpr, Ast.StringExpression("tonumber"));

    local function safeNumericExpression(valueExpr)
        return Ast.OrExpression(
            Ast.AndExpression(
                Ast.EqualsExpression(
                    Ast.FunctionCallExpression(typeExpr, {valueExpr}),
                    Ast.StringExpression("number")
                ),
                valueExpr
            ),
            Ast.OrExpression(
                Ast.AndExpression(
                    Ast.EqualsExpression(valueExpr, Ast.BooleanExpression(true)),
                    Ast.NumberExpression(1)
                ),
                Ast.OrExpression(
                    Ast.AndExpression(
                        Ast.EqualsExpression(valueExpr, Ast.BooleanExpression(false)),
                        Ast.NumberExpression(0)
                    ),
                    Ast.OrExpression(
                        Ast.FunctionCallExpression(tonumberExpr, {valueExpr}),
                        Ast.NumberExpression(0)
                    )
                )
            )
        );
    end

    local coercedLhs = safeNumericExpression(lhsVar);
    local coercedRhs = safeNumericExpression(rhsVar);
    return Ast[kind](coercedLhs, coercedRhs);
end

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope;
    local regs = {};
    for i = 1, numReturns do
        regs[i] = self:allocRegister();
        if i == 1 then
            local lhsReg = self:compileExpression(expression.lhs, funcDepth, 1)[1];
            local rhsReg = self:compileExpression(expression.rhs, funcDepth, 1)[1];

            local lhsVar = self:register(scope, lhsReg);
            local rhsVar = self:register(scope, rhsReg);
            
            local binaryExpr;
                if NUMERIC_ARITHMETIC_OPS[expression.kind] then
				binaryExpr = createTypeGuardedArithmetic(self, scope, lhsVar, rhsVar, expression.kind);
            else
				-- Non-arithmetic operations (comparisons, concatenation, etc.) are safe
				binaryExpr = Ast[expression.kind](lhsVar, rhsVar);
            end
            
            self:addStatement(self:setRegister(scope, regs[i], binaryExpr), {regs[i]}, {lhsReg, rhsReg}, true);
            self:freeRegister(rhsReg, false);
            self:freeRegister(lhsReg, false);
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false);
        end
    end
    return regs;
end;
