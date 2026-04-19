-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- string.lua
--
-- This Script contains the expression handler for the StringExpression.

local Ast = require("prometheus.ast");

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope;
    local regs = {};

    for i = 1, numReturns, 1 do
        regs[i] = self:allocRegister();
        if i == 1 then
            if self.enableVmStringEncoding and self.vmStringDecodeVar and self.registerVmString then
                scope:addReferenceToHigherScope(self.scope, self.vmStringDecodeVar);
                local stringId = self:registerVmString(expression.value);
                self:addStatement(self:setRegister(scope, regs[i], Ast.FunctionCallExpression(
                    Ast.VariableExpression(self.scope, self.vmStringDecodeVar),
                    {Ast.NumberExpression(stringId)}
                )), {regs[i]}, {}, false);
            else
                self:addStatement(self:setRegister(scope, regs[i], Ast.StringExpression(expression.value)), {regs[i]}, {}, false);
            end
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false);
        end
    end
    return regs;
end;

