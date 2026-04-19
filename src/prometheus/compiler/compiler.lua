-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- compiler.lua
--
-- This Script is the main compiler module.

local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local util = require("prometheus.util");

local lookupify = util.lookupify;
local AstKind = Ast.AstKind;

local unpack = unpack or table.unpack;

local blockModule = require("prometheus.compiler.block");
local registerModule = require("prometheus.compiler.register");
local upvalueModule = require("prometheus.compiler.upvalue");
local emitModule = require("prometheus.compiler.emit");
local compileCoreModule = require("prometheus.compiler.compile_core");

local Compiler = {};

function Compiler:new(options)
    options = options or {};

    local compiler = {
        blocks = {};
        registers = {};
        activeBlock = nil;
        registersForVar = {};
        usedRegisters = 0;
        maxUsedRegister = 0;
        registerVars = {};

        VAR_REGISTER = newproxy(false);
        RETURN_ALL = newproxy(false);
        POS_REGISTER = newproxy(false);
        RETURN_REGISTER = newproxy(false);
        UPVALUE = newproxy(false);

        BIN_OPS = lookupify{
            AstKind.LessThanExpression,
            AstKind.GreaterThanExpression,
            AstKind.LessThanOrEqualsExpression,
            AstKind.GreaterThanOrEqualsExpression,
            AstKind.NotEqualsExpression,
            AstKind.EqualsExpression,
            AstKind.StrCatExpression,
            AstKind.AddExpression,
            AstKind.SubExpression,
            AstKind.MulExpression,
            AstKind.DivExpression,
            AstKind.ModExpression,
            AstKind.PowExpression,
        };

        statementMergePasses = options.statementMergePasses or 4;
        enableParallelAssignmentMerge = options.enableParallelAssignmentMerge ~= false;
        shuffleBlocks = options.shuffleBlocks ~= false;
        enableStatementReorder = options.enableStatementReorder ~= false;
        enableBuiltinCapture = options.enableBuiltinCapture ~= false;
        enableHookGuard = options.enableHookGuard ~= false;
        guardNoisePasses = options.guardNoisePasses or 1;
        enableAntiTampering = options.enableAntiTampering ~= false;
        enableBlockIdEncoding = options.enableBlockIdEncoding ~= false;
        enableControlFlowBytecode = options.enableControlFlowBytecode ~= false;
        enablePackedControlFlowOperands = options.enablePackedControlFlowOperands ~= false;
        controlFlowBytecodeNoise = options.controlFlowBytecodeNoise or 1;
        strictEnvironmentChecks = options.strictEnvironmentChecks ~= false;
        dispatcherStyle = options.dispatcherStyle or "mixed";
        equalityDispatchMaxBlocks = options.equalityDispatchMaxBlocks or 16;
        dispatcherJunkBranches = options.dispatcherJunkBranches or 0;
        dispatcherJunkProbability = options.dispatcherJunkProbability or 0.6;
        dispatcherNoiseStatements = options.dispatcherNoiseStatements or 1;
    };

    setmetatable(compiler, self);
    self.__index = self;

    return compiler;
end

blockModule(Compiler);
registerModule(Compiler);
upvalueModule(Compiler);
emitModule(Compiler);
compileCoreModule(Compiler);

function Compiler:pushRegisterUsageInfo()
    table.insert(self.registerUsageStack, {
        usedRegisters = self.usedRegisters;
        registers = self.registers;
    });
    self.usedRegisters = 0;
    self.registers = {};
end

function Compiler:popRegisterUsageInfo()
    local info = table.remove(self.registerUsageStack);
    self.usedRegisters = info.usedRegisters;
    self.registers = info.registers;
end

function Compiler:initControlFlowCodec()
    if self.enableBlockIdEncoding then
        self.blockIdMultiplier = math.random(257, 8191);
        self.blockIdAdd = math.random(2^18, 2^24);
    else
        self.blockIdMultiplier = 1;
        self.blockIdAdd = 0;
    end

    if self.enableControlFlowBytecode then
        self.blockIdBytecodeOffset = math.random(2^14, 2^20);
        self.controlFlowPackRadix = math.random(257, 1021);
        self.controlFlowPackAddA = math.random(2^10, 2^18);
        self.controlFlowPackAddB = math.random(2^10, 2^18);
        self.controlFlowPackSwapOperands = math.random() > 0.5;
        self.controlFlowDescriptorBias = math.random(3, 23);
        self.controlFlowPackMulA = math.random(3, 19);
        self.controlFlowPackMulB = math.random(3, 19);
    else
        self.blockIdBytecodeOffset = 0;
        self.controlFlowPackRadix = 1;
        self.controlFlowPackAddA = 0;
        self.controlFlowPackAddB = 0;
        self.controlFlowPackSwapOperands = false;
        self.controlFlowDescriptorBias = 0;
        self.controlFlowPackMulA = 1;
        self.controlFlowPackMulB = 1;
    end
end

function Compiler:encodeBlockId(rawId)
    if self.enableBlockIdEncoding then
        return (rawId * self.blockIdMultiplier) + self.blockIdAdd;
    end
    return rawId;
end

function Compiler:encodePackedControlFlowEntry(target)
    local radix = self.controlFlowPackRadix or 257;
    local addA = self.controlFlowPackAddA or 0;
    local addB = self.controlFlowPackAddB or 0;
    local hi = math.floor(target / radix);
    local lo = target % radix;
    local descriptor = math.random(1, 3);
    local opA = hi + addA;
    local opB = lo + addB;
    if descriptor == 2 then
        opA = lo + addA;
        opB = hi + addB;
    elseif descriptor == 3 then
        local mulA = self.controlFlowPackMulA or 1;
        local mulB = self.controlFlowPackMulB or 1;
        opA = (hi * mulA) + addA;
        opB = (lo * mulB) + addB;
    end
    return {
        descriptor + (self.controlFlowDescriptorBias or 0),
        opA,
        opB,
    };
end

function Compiler:encodeControlFlowEntry(rawId)
    local target = rawId + (self.blockIdBytecodeOffset or 0);
    if self.enablePackedControlFlowOperands then
        return self:encodePackedControlFlowEntry(target);
    end
    return target;
end

function Compiler:createControlFlowBytecodeTableExpression()
    local entries = {};
    for i = 1, #self.blockIdValues do
        local value = self.blockIdValues[i];
        if type(value) == "table" then
            entries[i] = Ast.TableEntry(Ast.TableConstructorExpression({
                Ast.TableEntry(Ast.NumberExpression(value[1]));
                Ast.TableEntry(Ast.NumberExpression(value[2]));
                Ast.TableEntry(Ast.NumberExpression(value[3]));
            }));
        else
            entries[i] = Ast.TableEntry(Ast.NumberExpression(value));
        end
    end
    return Ast.TableConstructorExpression(entries);
end

function Compiler:decodeControlFlowEntryExpression(slotExpr)
    if self.enablePackedControlFlowOperands then
        local descExpr = Ast.SubExpression(
            Ast.IndexExpression(slotExpr, Ast.NumberExpression(1)),
            Ast.NumberExpression(self.controlFlowDescriptorBias or 0)
        );
        local opAExpr = Ast.IndexExpression(slotExpr, Ast.NumberExpression(2));
        local opBExpr = Ast.IndexExpression(slotExpr, Ast.NumberExpression(3));

        local decodeVariant1 = Ast.AddExpression(
            Ast.MulExpression(
                Ast.SubExpression(opAExpr, Ast.NumberExpression(self.controlFlowPackAddA or 0)),
                Ast.NumberExpression(self.controlFlowPackRadix or 257)
            ),
            Ast.SubExpression(opBExpr, Ast.NumberExpression(self.controlFlowPackAddB or 0))
        );
        local decodeVariant2 = Ast.AddExpression(
            Ast.MulExpression(
                Ast.SubExpression(opBExpr, Ast.NumberExpression(self.controlFlowPackAddB or 0)),
                Ast.NumberExpression(self.controlFlowPackRadix or 257)
            ),
            Ast.SubExpression(opAExpr, Ast.NumberExpression(self.controlFlowPackAddA or 0))
        );
        local decodeVariant3 = Ast.AddExpression(
            Ast.MulExpression(
                Ast.DivExpression(
                    Ast.SubExpression(opAExpr, Ast.NumberExpression(self.controlFlowPackAddA or 0)),
                    Ast.NumberExpression(self.controlFlowPackMulA or 1)
                ),
                Ast.NumberExpression(self.controlFlowPackRadix or 257)
            ),
            Ast.DivExpression(
                Ast.SubExpression(opBExpr, Ast.NumberExpression(self.controlFlowPackAddB or 0)),
                Ast.NumberExpression(self.controlFlowPackMulB or 1)
            )
        );
        local decodedWithOffset = Ast.OrExpression(
            Ast.AndExpression(
                Ast.EqualsExpression(descExpr, Ast.NumberExpression(3)),
                decodeVariant3
            ),
            Ast.OrExpression(
                Ast.AndExpression(
                    Ast.EqualsExpression(descExpr, Ast.NumberExpression(2)),
                    decodeVariant2
                ),
                decodeVariant1
            )
        );
        return Ast.SubExpression(decodedWithOffset, Ast.NumberExpression(self.blockIdBytecodeOffset or 0));
    end

    return Ast.SubExpression(slotExpr, Ast.NumberExpression(self.blockIdBytecodeOffset or 0));
end

function Compiler:compile(ast)
    self.blocks = {};
    self.registers = {};
    self.activeBlock = nil;
    self.registersForVar = {};
    self.scopeFunctionDepths = {};
    self.maxUsedRegister = 0;
    self.usedRegisters = 0;
    self.registerVars = {};
    self.usedBlockIds = {};

    self.upvalVars = {};
    self.registerUsageStack = {};
    self.blockIdValues = {};
    self.blockIdSlots = {};

    self.upvalsProxyLenReturn = math.random(-2^22, 2^22);

    self:initControlFlowCodec();

    local newGlobalScope = Scope:newGlobal();
    local psc = Scope:new(newGlobalScope, nil);

    local _, getfenvVar = newGlobalScope:resolve("getfenv");
    local _, tableVar = newGlobalScope:resolve("table");
    local _, unpackVar = newGlobalScope:resolve("unpack");
    local _, envVar = newGlobalScope:resolve("_ENV");
    local _, newproxyVar = newGlobalScope:resolve("newproxy");
    local _, setmetatableVar = newGlobalScope:resolve("setmetatable");
    local _, getmetatableVar = newGlobalScope:resolve("getmetatable");
    local _, selectVar = newGlobalScope:resolve("select");

    psc:addReferenceToHigherScope(newGlobalScope, getfenvVar, 2);
    psc:addReferenceToHigherScope(newGlobalScope, tableVar);
    psc:addReferenceToHigherScope(newGlobalScope, unpackVar);
    psc:addReferenceToHigherScope(newGlobalScope, envVar);
    psc:addReferenceToHigherScope(newGlobalScope, newproxyVar);
    psc:addReferenceToHigherScope(newGlobalScope, setmetatableVar);
    psc:addReferenceToHigherScope(newGlobalScope, getmetatableVar);

    self.scope = Scope:new(psc);
    self.envVar = self.scope:addVariable();
    self.containerFuncVar = self.scope:addVariable();
    self.unpackVar = self.scope:addVariable();
    self.newproxyVar = self.scope:addVariable();
    self.setmetatableVar = self.scope:addVariable();
    self.getmetatableVar = self.scope:addVariable();
    self.selectVar = self.scope:addVariable();
    self.blockIdBytecodeVar = self.scope:addVariable();

    local argVar = self.scope:addVariable();

    self.containerFuncScope = Scope:new(self.scope);
    self.whileScope = Scope:new(self.containerFuncScope);

    self.posVar = self.containerFuncScope:addVariable();
    self.argsVar = self.containerFuncScope:addVariable();
    self.currentUpvaluesVar = self.containerFuncScope:addVariable();
    self.detectGcCollectVar = self.containerFuncScope:addVariable();
    self.returnVar = self.containerFuncScope:addVariable();

    self.upvaluesTable = self.scope:addVariable();
    self.upvaluesReferenceCountsTable = self.scope:addVariable();
    self.allocUpvalFunction = self.scope:addVariable();
    self.currentUpvalId = self.scope:addVariable();

    self.upvaluesProxyFunctionVar = self.scope:addVariable();
    self.upvaluesGcFunctionVar = self.scope:addVariable();
    self.freeUpvalueFunc = self.scope:addVariable();

    self.createClosureVars = {};
    self.createVarargClosureVar = self.scope:addVariable();
    local createClosureScope = Scope:new(self.scope);
    local createClosurePosArg = createClosureScope:addVariable();
    local createClosureUpvalsArg = createClosureScope:addVariable();
    local createClosureProxyObject = createClosureScope:addVariable();
    local createClosureFuncVar = createClosureScope:addVariable();

    local createClosureSubScope = Scope:new(createClosureScope);

    local upvalEntries = {};
    local upvalueIds = {};
    self.getUpvalueId = function(self, scope, id)
        local expression;
        local scopeFuncDepth = self.scopeFunctionDepths[scope];
        if(scopeFuncDepth == 0) then
            if upvalueIds[id] then
                return upvalueIds[id];
            end
            expression = Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.allocUpvalFunction), {});
        else
            require("logger"):error("Unresolved Upvalue, this error should not occur!");
        end
        table.insert(upvalEntries, Ast.TableEntry(expression));
        local uid = #upvalEntries;
        upvalueIds[id] = uid;
        return uid;
    end

    createClosureSubScope:addReferenceToHigherScope(self.scope, self.containerFuncVar);
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosurePosArg)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureUpvalsArg, 1)
    createClosureScope:addReferenceToHigherScope(self.scope, self.upvaluesProxyFunctionVar)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureProxyObject);

    self:compileTopNode(ast);

    local functionNodeAssignments = {
        {
            var = Ast.AssignmentVariable(self.scope, self.containerFuncVar),
            val = Ast.FunctionLiteralExpression({
                Ast.VariableExpression(self.containerFuncScope, self.posVar),
                Ast.VariableExpression(self.containerFuncScope, self.argsVar),
                Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar),
                Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar)
            }, self:emitContainerFuncBody());
        }, {
            var = Ast.AssignmentVariable(self.scope, self.createVarargClosureVar),
            val = Ast.FunctionLiteralExpression({
                    Ast.VariableExpression(createClosureScope, createClosurePosArg),
                    Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
                },
                Ast.Block({
                    Ast.LocalVariableDeclaration(createClosureScope, {
                        createClosureProxyObject
                    }, {
                        Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar), {
                            Ast.VariableExpression(createClosureScope, createClosureUpvalsArg)
                        })
                    }),
                    Ast.LocalVariableDeclaration(createClosureScope, {createClosureFuncVar},{
                        Ast.FunctionLiteralExpression({
                            Ast.VarargExpression();
                        },
                        Ast.Block({
                            Ast.ReturnStatement{
                                Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.containerFuncVar), {
                                    Ast.VariableExpression(createClosureScope, createClosurePosArg),
                                    Ast.TableConstructorExpression({Ast.TableEntry(Ast.VarargExpression())}),
                                    Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
                                    Ast.VariableExpression(createClosureScope, createClosureProxyObject)
                                })
                            }
                        }, createClosureSubScope)
                        );
                    });
                    Ast.ReturnStatement{Ast.VariableExpression(createClosureScope, createClosureFuncVar)};
                }, createClosureScope)
            );
        }, {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesTable),
            val = Ast.TableConstructorExpression({}),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesReferenceCountsTable),
            val = Ast.TableConstructorExpression({}),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.allocUpvalFunction),
            val = self:createAllocUpvalFunction(),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.currentUpvalId),
            val = Ast.NumberExpression(0),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesProxyFunctionVar),
            val = self:createUpvaluesProxyFunc(),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesGcFunctionVar),
            val = self:createUpvaluesGcFunc(),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.freeUpvalueFunc),
            val = self:createFreeUpvalueFunc(),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdBytecodeVar),
            val = self:createControlFlowBytecodeTableExpression(),
        },
    }

    local tbl = {
        Ast.VariableExpression(self.scope, self.containerFuncVar),
        Ast.VariableExpression(self.scope, self.createVarargClosureVar),
        Ast.VariableExpression(self.scope, self.upvaluesTable),
        Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable),
        Ast.VariableExpression(self.scope, self.allocUpvalFunction),
        Ast.VariableExpression(self.scope, self.currentUpvalId),
        Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar),
        Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar),
        Ast.VariableExpression(self.scope, self.freeUpvalueFunc),
        Ast.VariableExpression(self.scope, self.blockIdBytecodeVar),
    };
    for i, entry in pairs(self.createClosureVars) do
        table.insert(functionNodeAssignments, entry);
        table.insert(tbl, Ast.VariableExpression(entry.var.scope, entry.var.id));
    end

    util.shuffle(functionNodeAssignments);
    local assignmentStatLhs, assignmentStatRhs = {}, {};
    for i, v in ipairs(functionNodeAssignments) do
        assignmentStatLhs[i] = v.var;
        assignmentStatRhs[i] = v.val;
    end


    -- NEW: Position Shuffler
    local ids = util.shuffle({1, 2, 3, 4, 5, 6, 7});

    local items = {
        Ast.VariableExpression(self.scope, self.envVar),
        Ast.VariableExpression(self.scope, self.unpackVar),
        Ast.VariableExpression(self.scope, self.newproxyVar),
        Ast.VariableExpression(self.scope, self.setmetatableVar),
        Ast.VariableExpression(self.scope, self.getmetatableVar),
        Ast.VariableExpression(self.scope, self.selectVar),
        Ast.VariableExpression(self.scope, argVar),
    }

    local astItems = {
        Ast.OrExpression(Ast.AndExpression(Ast.VariableExpression(newGlobalScope, getfenvVar), Ast.FunctionCallExpression(Ast.VariableExpression(newGlobalScope, getfenvVar), {})), Ast.VariableExpression(newGlobalScope, envVar));
        Ast.OrExpression(Ast.VariableExpression(newGlobalScope, unpackVar), Ast.IndexExpression(Ast.VariableExpression(newGlobalScope, tableVar), Ast.StringExpression("unpack")));
        Ast.VariableExpression(newGlobalScope, newproxyVar);
        Ast.VariableExpression(newGlobalScope, setmetatableVar);
        Ast.VariableExpression(newGlobalScope, getmetatableVar);
        Ast.VariableExpression(newGlobalScope, selectVar);
        Ast.TableConstructorExpression({
            Ast.TableEntry(Ast.VarargExpression());
        })
    }

    local functionNode = Ast.FunctionLiteralExpression({
      items[ids[1]], items[ids[2]], items[ids[3]], items[ids[4]],
      items[ids[5]], items[ids[6]], items[ids[7]],
      unpack(util.shuffle(tbl))
    }, Ast.Block({
        Ast.AssignmentStatement(assignmentStatLhs, assignmentStatRhs);
        Ast.ReturnStatement{
            Ast.FunctionCallExpression(Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.createVarargClosureVar), {
                    self:blockIdExpression(self.scope, self.startBlockId);
                    Ast.TableConstructorExpression(upvalEntries);
                }), {Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {Ast.VariableExpression(self.scope, argVar)})});
        }
    }, self.scope));

    return Ast.TopNode(Ast.Block({
        Ast.ReturnStatement{Ast.FunctionCallExpression(functionNode, {
            astItems[ids[1]], astItems[ids[2]], astItems[ids[3]], astItems[ids[4]],
            astItems[ids[5]], astItems[ids[6]], astItems[ids[7]],
        })};
    }, psc), newGlobalScope);
end

function Compiler:getCreateClosureVar(argCount)
    if not self.createClosureVars[argCount] then
        local var = Ast.AssignmentVariable(self.scope, self.scope:addVariable());
        local createClosureScope = Scope:new(self.scope);
        local createClosureSubScope = Scope:new(createClosureScope);

        local createClosurePosArg = createClosureScope:addVariable();
        local createClosureUpvalsArg = createClosureScope:addVariable();
        local createClosureProxyObject = createClosureScope:addVariable();
        local createClosureFuncVar = createClosureScope:addVariable();

        createClosureSubScope:addReferenceToHigherScope(self.scope, self.containerFuncVar);
        createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosurePosArg)
        createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureUpvalsArg, 1)
        createClosureScope:addReferenceToHigherScope(self.scope, self.upvaluesProxyFunctionVar)
        createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureProxyObject);

        local  argsTb, argsTb2 = {}, {};
        for i = 1, argCount do
            local arg = createClosureSubScope:addVariable()
            argsTb[i] = Ast.VariableExpression(createClosureSubScope, arg);
            argsTb2[i] = Ast.TableEntry(Ast.VariableExpression(createClosureSubScope, arg));
        end

        local val = Ast.FunctionLiteralExpression({
            Ast.VariableExpression(createClosureScope, createClosurePosArg),
            Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
        }, Ast.Block({
                Ast.LocalVariableDeclaration(createClosureScope, {
                    createClosureProxyObject
                }, {
                    Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar), {
                        Ast.VariableExpression(createClosureScope, createClosureUpvalsArg)
                    })
                }),
                Ast.LocalVariableDeclaration(createClosureScope, {createClosureFuncVar},{
                    Ast.FunctionLiteralExpression(argsTb,
                    Ast.Block({
                        Ast.ReturnStatement{
                            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.containerFuncVar), {
                                Ast.VariableExpression(createClosureScope, createClosurePosArg),
                                Ast.TableConstructorExpression(argsTb2),
                                Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
                                Ast.VariableExpression(createClosureScope, createClosureProxyObject)
                            })
                        }
                    }, createClosureSubScope)
                    );
                });
                Ast.ReturnStatement{Ast.VariableExpression(createClosureScope, createClosureFuncVar)}
            }, createClosureScope)
        );
        self.createClosureVars[argCount] = {
            var = var,
            val = val,
        }
    end


    local var = self.createClosureVars[argCount].var;
    return var.scope, var.id;
end

return Compiler;
