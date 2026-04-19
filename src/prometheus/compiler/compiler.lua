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
        enableControlFlowSlotAliasing = options.enableControlFlowSlotAliasing ~= false;
        enableVmStringEncoding = options.enableVmStringEncoding ~= false;
        optimizeVM = options.optimizeVM ~= false;
        adaptiveDifficulty = options.adaptiveDifficulty ~= false;
        jitResistantControlFlow = options.jitResistantControlFlow ~= false;
        enableEntropyInjection = options.enableEntropyInjection ~= false;
        vmStringChunkSize = options.vmStringChunkSize or 24;
        controlFlowBytecodeNoise = options.controlFlowBytecodeNoise or 1;
        dispatchIdModulus = options.dispatchIdModulus or (2^24);
        strictEnvironmentChecks = options.strictEnvironmentChecks ~= false;
        dispatcherStyle = options.dispatcherStyle or "mixed";
        equalityDispatchMaxBlocks = options.equalityDispatchMaxBlocks or 16;
        dispatcherJunkBranches = options.dispatcherJunkBranches or 0;
        dispatcherJunkProbability = options.dispatcherJunkProbability or 0.6;
        dispatcherNoiseStatements = options.dispatcherNoiseStatements or 1;
        enableControlFlowBlobStorage = options.enableControlFlowBlobStorage == true;
        controlFlowBlobPageSize = options.controlFlowBlobPageSize or 24;
        controlFlowBlobCacheSize = options.controlFlowBlobCacheSize or 12;
    };

    compiler.enableControlFlowIndexIndirection = options.enableControlFlowIndexIndirection;
    if compiler.enableControlFlowIndexIndirection == nil then
        compiler.enableControlFlowIndexIndirection = compiler.optimizeVM or compiler.enableControlFlowSlotAliasing;
    end
    compiler.enableControlFlowPayloadPermutation = options.enableControlFlowPayloadPermutation;
    if compiler.enableControlFlowPayloadPermutation == nil then
        compiler.enableControlFlowPayloadPermutation = compiler.optimizeVM;
    end
    if compiler.enableControlFlowPayloadPermutation then
        compiler.enableControlFlowIndexIndirection = true;
    end
    if compiler.enableControlFlowBlobStorage then
        compiler.enableControlFlowIndexIndirection = true;
    end
    if not compiler.enableControlFlowBytecode then
        compiler.enableControlFlowIndexIndirection = false;
        compiler.enableControlFlowPayloadPermutation = false;
        compiler.enableControlFlowBlobStorage = false;
    end

    if compiler.optimizeVM then
        compiler.controlFlowBytecodeNoise = 0;
        compiler.dispatchIdModulus = options.dispatchIdModulus or (2^24);
        compiler.dispatcherJunkBranches = 0;
        compiler.dispatcherJunkProbability = 0;
        compiler.dispatcherNoiseStatements = 0;
    end

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
        if self.optimizeVM then
            self.dispatchIdStride = math.random(3, (2^16));
            if self.dispatchIdStride % 2 == 0 then
                self.dispatchIdStride = self.dispatchIdStride + 1;
            end
            self.dispatchIdSalt = math.random(1, self.dispatchIdModulus - 1);
            self.blockIdMultiplier = 1;
            self.blockIdAdd = 0;
        else
            self.blockIdMultiplier = math.random(257, 8191);
            self.blockIdAdd = math.random(2^18, 2^24);
            self.dispatchIdStride = 1;
            self.dispatchIdSalt = 0;
        end
    else
        self.blockIdMultiplier = 1;
        self.blockIdAdd = 0;
        self.dispatchIdStride = 1;
        self.dispatchIdSalt = 0;
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
        self.controlFlowStorageMask = math.random(2^18, 2^23);
        self.controlFlowStorageMaskA = math.random(2^9, 2^15);
        self.controlFlowStorageMaskB = math.random(2^9, 2^15);
        self.controlFlowStorageMaskC = math.random(2^9, 2^15);
        if self.enableControlFlowIndexIndirection then
            self.controlFlowLookupStride = math.random(3, (2^16));
            if self.controlFlowLookupStride % 2 == 0 then
                self.controlFlowLookupStride = self.controlFlowLookupStride + 1;
            end
            self.controlFlowLookupSalt = math.random(1, (self.dispatchIdModulus or (2^24)) - 1);
            self.controlFlowIndexMask = math.random(2^10, 2^16);
        else
            self.controlFlowLookupStride = 1;
            self.controlFlowLookupSalt = 0;
            self.controlFlowIndexMask = 0;
        end
        if self.enableControlFlowPayloadPermutation then
            self.controlFlowPayloadStride = math.random(3, (2^16));
            if self.controlFlowPayloadStride % 2 == 0 then
                self.controlFlowPayloadStride = self.controlFlowPayloadStride + 1;
            end
            self.controlFlowPayloadSalt = math.random(1, (self.dispatchIdModulus or (2^24)) - 1);
        else
            self.controlFlowPayloadStride = 1;
            self.controlFlowPayloadSalt = 0;
        end
        if self.enableControlFlowBlobStorage then
            self.controlFlowBlobKey = math.random(43, 223);
        else
            self.controlFlowBlobKey = 0;
        end
        if self.enableControlFlowSlotAliasing then
            self.controlFlowAliasOffset = math.random(2^10, 2^16);
        else
            self.controlFlowAliasOffset = 0;
        end
    else
        self.blockIdBytecodeOffset = 0;
        self.controlFlowPackRadix = 1;
        self.controlFlowPackAddA = 0;
        self.controlFlowPackAddB = 0;
        self.controlFlowPackSwapOperands = false;
        self.controlFlowDescriptorBias = 0;
        self.controlFlowPackMulA = 1;
        self.controlFlowPackMulB = 1;
        self.controlFlowStorageMask = 0;
        self.controlFlowStorageMaskA = 0;
        self.controlFlowStorageMaskB = 0;
        self.controlFlowStorageMaskC = 0;
        self.controlFlowLookupStride = 1;
        self.controlFlowLookupSalt = 0;
        self.controlFlowIndexMask = 0;
        self.controlFlowPayloadStride = 1;
        self.controlFlowPayloadSalt = 0;
        self.controlFlowBlobKey = 0;
        self.controlFlowAliasOffset = 0;
    end
end

function Compiler:encodeBlockId(rawId)
    if self.enableBlockIdEncoding then
        if self.optimizeVM then
            local modulus = self.dispatchIdModulus or (2^24);
            return ((rawId * (self.dispatchIdStride or 1)) + (self.dispatchIdSalt or 0)) % modulus + 1;
        end
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

function Compiler:obfuscateControlFlowStorageValue(value)
    if type(value) == "table" then
        return {
            (value[1] or 0) + (self.controlFlowStorageMaskA or 0),
            (value[2] or 0) + (self.controlFlowStorageMaskB or 0),
            (value[3] or 0) + (self.controlFlowStorageMaskC or 0),
        };
    end
    return value + (self.controlFlowStorageMask or 0);
end

function Compiler:encodeControlFlowLookupSlot(slot)
    if not self.enableControlFlowIndexIndirection then
        return slot;
    end
    local modulus = self.dispatchIdModulus or (2^24);
    return ((slot * (self.controlFlowLookupStride or 1)) + (self.controlFlowLookupSalt or 0)) % modulus + 1;
end

function Compiler:encodeControlFlowPayloadSlot(slot)
    if not self.enableControlFlowPayloadPermutation then
        return slot;
    end
    local modulus = self.dispatchIdModulus or (2^24);
    return ((slot * (self.controlFlowPayloadStride or 1)) + (self.controlFlowPayloadSalt or 0)) % modulus + 1;
end

function Compiler:ensureControlFlowBlobData()
    if self.controlFlowBlobEncodedData and self.controlFlowBlobOffsetsData then
        return self.controlFlowBlobEncodedData, self.controlFlowBlobOffsetsData;
    end

    local pageSize = math.max(1, math.floor(self.controlFlowBlobPageSize or 24));
    local blobParts = {};
    local offsets = {};
    local runningOffset = 1;

    local function serializeEntry(value)
        if type(value) == "table" then
            return string.format("{%s,%s,%s}", tostring(value[1] or 0), tostring(value[2] or 0), tostring(value[3] or 0));
        end
        return tostring(value);
    end

    local pageIndex = 0;
    for i = 1, #self.controlFlowBytecodeEntries, pageSize do
        pageIndex = pageIndex + 1;
        local upper = math.min(i + pageSize - 1, #self.controlFlowBytecodeEntries);
        local serialized = {};
        for j = i, upper do
            serialized[#serialized + 1] = serializeEntry(self.controlFlowBytecodeEntries[j].value);
        end

        local pageSource = "return {" .. table.concat(serialized, ",") .. "}";
        local encodedChars = {};
        local baseKey = (self.controlFlowBlobKey or 0) + pageIndex;
        for pos = 1, #pageSource do
            local byte = string.byte(pageSource, pos);
            local delta = (baseKey + (pos % 17)) % 251;
            encodedChars[#encodedChars + 1] = string.char((byte + delta) % 256);
        end

        local encodedPage = table.concat(encodedChars);
        blobParts[#blobParts + 1] = encodedPage;
        offsets[#offsets + 1] = runningOffset;
        offsets[#offsets + 1] = #encodedPage;
        runningOffset = runningOffset + #encodedPage;
    end

    self.controlFlowBlobEncodedData = table.concat(blobParts);
    self.controlFlowBlobOffsetsData = offsets;
    return self.controlFlowBlobEncodedData, self.controlFlowBlobOffsetsData;
end

function Compiler:createControlFlowBlobExpression()
    if self.controlFlowBlobExpressionCache then
        return self.controlFlowBlobExpressionCache;
    end
    local blob = self:ensureControlFlowBlobData();
    local chunkSize = math.max(1, math.floor(self.vmStringChunkSize or 24));
    if #blob <= chunkSize then
        self.controlFlowBlobExpressionCache = Ast.StringExpression(blob);
        return self.controlFlowBlobExpressionCache;
    end

    local expr = Ast.StringExpression(string.sub(blob, 1, chunkSize));
    for i = chunkSize + 1, #blob, chunkSize do
        expr = Ast.StrCatExpression(expr, Ast.StringExpression(string.sub(blob, i, i + chunkSize - 1)));
    end
    self.controlFlowBlobExpressionCache = expr;
    return self.controlFlowBlobExpressionCache;
end

function Compiler:createControlFlowBlobOffsetsExpression()
    if self.controlFlowBlobOffsetsExpressionCache then
        return self.controlFlowBlobOffsetsExpressionCache;
    end
    local _, offsets = self:ensureControlFlowBlobData();
    local entries = {};
    for i = 1, #offsets do
        entries[#entries + 1] = Ast.TableEntry(Ast.NumberExpression(offsets[i]));
    end
    self.controlFlowBlobOffsetsExpressionCache = Ast.TableConstructorExpression(entries);
    return self.controlFlowBlobOffsetsExpressionCache;
end

function Compiler:createControlFlowBlobDecodeFunctionExpression()
    if self.controlFlowBlobDecodeFunctionExpressionCache then
        return self.controlFlowBlobDecodeFunctionExpressionCache;
    end

    local fnScope = Scope:new(self.scope);
    local indexVar = fnScope:addVariable();
    local pageSizeVar = fnScope:addVariable();
    local pageVar = fnScope:addVariable();
    local withinVar = fnScope:addVariable();
    local cacheVar = fnScope:addVariable();
    local pageDataVar = fnScope:addVariable();
    local pairIndexVar = fnScope:addVariable();
    local startVar = fnScope:addVariable();
    local lenVar = fnScope:addVariable();
    local segmentVar = fnScope:addVariable();
    local posVar = fnScope:addVariable();
    local decodedVar = fnScope:addVariable();
    local loaderVar = fnScope:addVariable();
    local chunkVar = fnScope:addVariable();
    local countVar = fnScope:addVariable();
    local resetTableVar = fnScope:addVariable();

    fnScope:addReferenceToHigherScope(self.scope, self.blockIdBytecodeVar);
    fnScope:addReferenceToHigherScope(self.scope, self.blockIdBlobOffsetsVar);
    fnScope:addReferenceToHigherScope(self.scope, self.blockIdBlobCacheVar);
    fnScope:addReferenceToHigherScope(self.scope, self.envVar);
    fnScope:addReferenceToHigherScope(self.scope, self.getmetatableVar);

    local callbackScope = Scope:new(fnScope);
    local chVar = callbackScope:addVariable();
    callbackScope:addReferenceToHigherScope(fnScope, posVar);
    callbackScope:addReferenceToHigherScope(fnScope, pageVar);

    local envExpr = self:env(fnScope);
    local stringTableExpr = Ast.OrExpression(
        Ast.IndexExpression(envExpr, Ast.StringExpression("string")),
        Ast.IndexExpression(
            Ast.FunctionCallExpression(
                Ast.VariableExpression(self.scope, self.getmetatableVar),
                {Ast.StringExpression("")}
            ),
            Ast.StringExpression("__index")
        )
    );
    local byteExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("byte"));
    local charExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("char"));
    local subExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("sub"));
    local gsubExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("gsub"));
    local typeExpr = Ast.IndexExpression(envExpr, Ast.StringExpression("type"));
    local floorExpr = Ast.IndexExpression(
        Ast.IndexExpression(envExpr, Ast.StringExpression("math")),
        Ast.StringExpression("floor")
    );

    local decodeByteExpr = Ast.ModExpression(
        Ast.SubExpression(
            Ast.FunctionCallExpression(byteExpr, {Ast.VariableExpression(callbackScope, chVar)}),
            Ast.ModExpression(
                Ast.AddExpression(
                    Ast.AddExpression(
                        Ast.NumberExpression(self.controlFlowBlobKey or 0),
                        Ast.VariableExpression(fnScope, pageVar)
                    ),
                    Ast.ModExpression(Ast.VariableExpression(fnScope, posVar), Ast.NumberExpression(17))
                ),
                Ast.NumberExpression(251)
            )
        ),
        Ast.NumberExpression(256)
    );

    local callbackLiteral = Ast.FunctionLiteralExpression({
        Ast.VariableExpression(callbackScope, chVar),
    }, Ast.Block({
        Ast.AssignmentStatement({
            Ast.AssignmentVariable(fnScope, posVar)
        }, {
            Ast.AddExpression(Ast.VariableExpression(fnScope, posVar), Ast.NumberExpression(1))
        }),
        Ast.ReturnStatement{
            Ast.FunctionCallExpression(charExpr, {decodeByteExpr})
        }
    }, callbackScope));

    self.controlFlowBlobDecodeFunctionExpressionCache = Ast.FunctionLiteralExpression({
        Ast.VariableExpression(fnScope, indexVar),
    }, Ast.Block({
        Ast.LocalVariableDeclaration(fnScope, {pageSizeVar}, {Ast.NumberExpression(math.max(1, math.floor(self.controlFlowBlobPageSize or 24)))}),
        Ast.LocalVariableDeclaration(fnScope, {pageVar}, {
            Ast.AddExpression(
                Ast.FunctionCallExpression(floorExpr, {
                    Ast.DivExpression(
                        Ast.SubExpression(Ast.VariableExpression(fnScope, indexVar), Ast.NumberExpression(1)),
                        Ast.VariableExpression(fnScope, pageSizeVar)
                    )
                }),
                Ast.NumberExpression(1)
            )
        }),
        Ast.LocalVariableDeclaration(fnScope, {withinVar}, {
            Ast.AddExpression(
                Ast.ModExpression(
                    Ast.SubExpression(Ast.VariableExpression(fnScope, indexVar), Ast.NumberExpression(1)),
                    Ast.VariableExpression(fnScope, pageSizeVar)
                ),
                Ast.NumberExpression(1)
            )
        }),
        Ast.LocalVariableDeclaration(fnScope, {cacheVar}, {Ast.VariableExpression(self.scope, self.blockIdBlobCacheVar)}),
        Ast.LocalVariableDeclaration(fnScope, {pageDataVar}, {
            Ast.IndexExpression(Ast.VariableExpression(fnScope, cacheVar), Ast.VariableExpression(fnScope, pageVar))
        }),
        Ast.IfStatement(
            Ast.NotExpression(Ast.VariableExpression(fnScope, pageDataVar)),
            Ast.Block({
                Ast.LocalVariableDeclaration(fnScope, {pairIndexVar}, {
                    Ast.SubExpression(
                        Ast.MulExpression(Ast.VariableExpression(fnScope, pageVar), Ast.NumberExpression(2)),
                        Ast.NumberExpression(1)
                    )
                }),
                Ast.LocalVariableDeclaration(fnScope, {startVar, lenVar}, {
                    Ast.IndexExpression(Ast.VariableExpression(self.scope, self.blockIdBlobOffsetsVar), Ast.VariableExpression(fnScope, pairIndexVar)),
                    Ast.IndexExpression(
                        Ast.VariableExpression(self.scope, self.blockIdBlobOffsetsVar),
                        Ast.AddExpression(Ast.VariableExpression(fnScope, pairIndexVar), Ast.NumberExpression(1))
                    )
                }),
                Ast.LocalVariableDeclaration(fnScope, {segmentVar}, {
                    Ast.FunctionCallExpression(subExpr, {
                        Ast.VariableExpression(self.scope, self.blockIdBytecodeVar),
                        Ast.VariableExpression(fnScope, startVar),
                        Ast.SubExpression(
                            Ast.AddExpression(Ast.VariableExpression(fnScope, startVar), Ast.VariableExpression(fnScope, lenVar)),
                            Ast.NumberExpression(1)
                        )
                    })
                }),
                Ast.LocalVariableDeclaration(fnScope, {posVar}, {Ast.NumberExpression(0)}),
                Ast.LocalVariableDeclaration(fnScope, {decodedVar}, {
                    Ast.FunctionCallExpression(gsubExpr, {
                        Ast.VariableExpression(fnScope, segmentVar),
                        Ast.StringExpression("[%z\1-\255]"),
                        callbackLiteral,
                    })
                }),
                Ast.LocalVariableDeclaration(fnScope, {loaderVar}, {
                    Ast.OrExpression(
                        Ast.IndexExpression(self:env(fnScope), Ast.StringExpression("loadstring")),
                        Ast.IndexExpression(self:env(fnScope), Ast.StringExpression("load"))
                    )
                }),
                Ast.LocalVariableDeclaration(fnScope, {chunkVar}, {
                    Ast.AndExpression(
                        Ast.VariableExpression(fnScope, loaderVar),
                        Ast.FunctionCallExpression(Ast.VariableExpression(fnScope, loaderVar), {Ast.VariableExpression(fnScope, decodedVar)})
                    )
                }),
                Ast.LocalVariableDeclaration(fnScope, {pageDataVar}, {
                    Ast.AndExpression(
                        Ast.EqualsExpression(
                            Ast.FunctionCallExpression(typeExpr, {Ast.VariableExpression(fnScope, chunkVar)}),
                            Ast.StringExpression("function")
                        ),
                        Ast.FunctionCallExpression(Ast.VariableExpression(fnScope, chunkVar), {})
                    )
                }),
                Ast.IfStatement(
                    Ast.NotEqualsExpression(
                        Ast.FunctionCallExpression(typeExpr, {Ast.VariableExpression(fnScope, pageDataVar)}),
                        Ast.StringExpression("table")
                    ),
                    Ast.Block({
                        Ast.AssignmentStatement({Ast.AssignmentVariable(fnScope, pageDataVar)}, {Ast.TableConstructorExpression({})})
                    }, Scope:new(fnScope)),
                    {},
                    nil
                ),
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(fnScope, cacheVar), Ast.VariableExpression(fnScope, pageVar))
                }, {
                    Ast.VariableExpression(fnScope, pageDataVar)
                }),
                Ast.LocalVariableDeclaration(fnScope, {countVar}, {
                    Ast.AddExpression(
                        Ast.OrExpression(
                            Ast.IndexExpression(Ast.VariableExpression(fnScope, cacheVar), Ast.StringExpression("__count")),
                            Ast.NumberExpression(0)
                        ),
                        Ast.NumberExpression(1)
                    )
                }),
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(fnScope, cacheVar), Ast.StringExpression("__count"))
                }, {
                    Ast.VariableExpression(fnScope, countVar)
                }),
                Ast.IfStatement(
                    Ast.GreaterThanExpression(Ast.VariableExpression(fnScope, countVar), Ast.NumberExpression(math.max(1, math.floor(self.controlFlowBlobCacheSize or 12)))),
                    Ast.Block({
                        Ast.LocalVariableDeclaration(fnScope, {resetTableVar}, {Ast.TableConstructorExpression({})}),
                        Ast.AssignmentStatement({
                            Ast.AssignmentIndexing(Ast.VariableExpression(fnScope, resetTableVar), Ast.VariableExpression(fnScope, pageVar)),
                            Ast.AssignmentIndexing(Ast.VariableExpression(fnScope, resetTableVar), Ast.StringExpression("__count"))
                        }, {
                            Ast.VariableExpression(fnScope, pageDataVar),
                            Ast.NumberExpression(1)
                        }),
                        Ast.AssignmentStatement({
                            Ast.AssignmentVariable(self.scope, self.blockIdBlobCacheVar),
                            Ast.AssignmentVariable(fnScope, cacheVar)
                        }, {
                            Ast.VariableExpression(fnScope, resetTableVar),
                            Ast.VariableExpression(fnScope, resetTableVar)
                        }),
                    }, Scope:new(fnScope)),
                    {},
                    nil
                ),
            }, Scope:new(fnScope)),
            {},
            nil
        ),
        Ast.ReturnStatement{
            Ast.IndexExpression(Ast.VariableExpression(fnScope, pageDataVar), Ast.VariableExpression(fnScope, withinVar))
        },
    }, fnScope));

    return self.controlFlowBlobDecodeFunctionExpressionCache;
end

function Compiler:createControlFlowBytecodeTableExpression()
	if self.controlFlowBytecodeTableExpressionCache then
		return self.controlFlowBytecodeTableExpressionCache;
	end
    local entries = {};
    for i = 1, #self.controlFlowBytecodeEntries do
        local entry = self.controlFlowBytecodeEntries[i];
        local value = entry.value;
        if type(value) == "table" then
            local valueExpr = Ast.TableConstructorExpression({
                Ast.TableEntry(Ast.NumberExpression(value[1]));
                Ast.TableEntry(Ast.NumberExpression(value[2]));
                Ast.TableEntry(Ast.NumberExpression(value[3]));
            });
            if self.enableControlFlowPayloadPermutation then
                entries[#entries + 1] = Ast.KeyedTableEntry(
                    Ast.NumberExpression(entry.payloadSlot or entry.slot or i),
                    valueExpr
                );
            else
                entries[#entries + 1] = Ast.TableEntry(valueExpr);
            end
        else
            local valueExpr = Ast.NumberExpression(value);
            if self.enableControlFlowPayloadPermutation then
                entries[#entries + 1] = Ast.KeyedTableEntry(
                    Ast.NumberExpression(entry.payloadSlot or entry.slot or i),
                    valueExpr
                );
            else
                entries[#entries + 1] = Ast.TableEntry(valueExpr);
            end
        end
    end
	self.controlFlowBytecodeTableExpressionCache = Ast.TableConstructorExpression(entries);
	return self.controlFlowBytecodeTableExpressionCache;
end

function Compiler:createControlFlowIndexTableExpression()
	if self.controlFlowIndexTableExpressionCache then
		return self.controlFlowIndexTableExpressionCache;
	end
    local entries = {};
    for i = 1, #self.controlFlowBytecodeEntries do
        local entry = self.controlFlowBytecodeEntries[i];
        local lookupSlot = entry.lookupSlot or entry.aliasSlot or entry.slot;
        local payloadSlot;
        if self.enableControlFlowBlobStorage then
            payloadSlot = entry.slot or i;
        else
            payloadSlot = entry.payloadSlot or entry.slot or i;
        end
        entries[#entries + 1] = Ast.KeyedTableEntry(
            Ast.NumberExpression(lookupSlot),
            Ast.NumberExpression(payloadSlot + (self.controlFlowIndexMask or 0))
        );
    end
	self.controlFlowIndexTableExpressionCache = Ast.TableConstructorExpression(entries);
	return self.controlFlowIndexTableExpressionCache;
end

function Compiler:decodeControlFlowEntryExpression(slotExpr)
    if self.enablePackedControlFlowOperands then
        local descExpr = Ast.SubExpression(
            Ast.IndexExpression(slotExpr, Ast.NumberExpression(1)),
            Ast.NumberExpression((self.controlFlowDescriptorBias or 0) + (self.controlFlowStorageMaskA or 0))
        );
        local opAExpr = Ast.SubExpression(
            Ast.IndexExpression(slotExpr, Ast.NumberExpression(2)),
            Ast.NumberExpression(self.controlFlowStorageMaskB or 0)
        );
        local opBExpr = Ast.SubExpression(
            Ast.IndexExpression(slotExpr, Ast.NumberExpression(3)),
            Ast.NumberExpression(self.controlFlowStorageMaskC or 0)
        );

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

    return Ast.SubExpression(
        slotExpr,
        Ast.NumberExpression((self.blockIdBytecodeOffset or 0) + (self.controlFlowStorageMask or 0))
    );
end

function Compiler:registerVmString(value)
    local cached = self.vmStringPoolIndex[value];
    if cached then
        return cached;
    end
    self.vmStringBlobExpressionCache = nil;
    self.vmStringOffsetsExpressionCache = nil;
    self.vmStringDecodeFunctionExpressionCache = nil;
    local idx = #self.vmStringPool + 1;
    self.vmStringPool[idx] = value;
    self.vmStringPoolIndex[value] = idx;
    return idx;
end

function Compiler:createVmStringBlobExpression()
	if self.vmStringBlobExpressionCache then
		return self.vmStringBlobExpressionCache;
	end
    local parts = {};
    local key = self.vmStringKey or 97;
    for idx, value in ipairs(self.vmStringPool) do
        local len = #value;
        for pos = 1, len do
            local byte = string.byte(value, pos);
            local delta = key + ((idx + pos) % 17);
            parts[#parts + 1] = string.char((byte + delta) % 256);
        end
    end
    local blob = table.concat(parts);
    local chunkSize = math.max(1, math.floor(self.vmStringChunkSize or 24));
    if #blob <= chunkSize then
		self.vmStringBlobExpressionCache = Ast.StringExpression(blob);
		return self.vmStringBlobExpressionCache;
    end

    local expr = Ast.StringExpression(string.sub(blob, 1, chunkSize));
    for i = chunkSize + 1, #blob, chunkSize do
        expr = Ast.StrCatExpression(expr, Ast.StringExpression(string.sub(blob, i, i + chunkSize - 1)));
    end
	self.vmStringBlobExpressionCache = expr;
	return self.vmStringBlobExpressionCache;
end

function Compiler:createVmStringOffsetsExpression()
	if self.vmStringOffsetsExpressionCache then
		return self.vmStringOffsetsExpressionCache;
	end
    local entries = {};
    local offset = 1;
    for _, value in ipairs(self.vmStringPool) do
        local len = #value;
        entries[#entries + 1] = Ast.TableEntry(Ast.NumberExpression(offset));
        entries[#entries + 1] = Ast.TableEntry(Ast.NumberExpression(len));
        offset = offset + len;
    end
	self.vmStringOffsetsExpressionCache = Ast.TableConstructorExpression(entries);
	return self.vmStringOffsetsExpressionCache;
end

function Compiler:createVmStringDecodeFunctionExpression()
	if self.vmStringDecodeFunctionExpressionCache then
		return self.vmStringDecodeFunctionExpressionCache;
	end
    local fnScope = Scope:new(self.scope);
    local idxVar = fnScope:addVariable();
    local pairIndexVar = fnScope:addVariable();
    local startVar = fnScope:addVariable();
    local lenVar = fnScope:addVariable();
    local segmentVar = fnScope:addVariable();
    local posVar = fnScope:addVariable();
    local decodedVar = fnScope:addVariable();

    fnScope:addReferenceToHigherScope(self.scope, self.vmStringBlobVar);
    fnScope:addReferenceToHigherScope(self.scope, self.vmStringOffsetsVar);
    fnScope:addReferenceToHigherScope(self.scope, self.getmetatableVar);

    local callbackScope = Scope:new(fnScope);
    local chVar = callbackScope:addVariable();
    callbackScope:addReferenceToHigherScope(fnScope, posVar);
    callbackScope:addReferenceToHigherScope(fnScope, idxVar);

    local envExpr = self:env(fnScope);
    local stringTableExpr = Ast.OrExpression(
        Ast.IndexExpression(envExpr, Ast.StringExpression("string")),
        Ast.IndexExpression(
            Ast.FunctionCallExpression(
                Ast.VariableExpression(self.scope, self.getmetatableVar),
                {Ast.StringExpression("")}
            ),
            Ast.StringExpression("__index")
        )
    );
    local byteExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("byte"));
    local charExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("char"));
    local subExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("sub"));
    local gsubExpr = Ast.IndexExpression(stringTableExpr, Ast.StringExpression("gsub"));

    local decodeByteExpr = Ast.ModExpression(
        Ast.SubExpression(
            Ast.FunctionCallExpression(byteExpr, {Ast.VariableExpression(callbackScope, chVar)}),
            Ast.AddExpression(
                Ast.NumberExpression(self.vmStringKey or 97),
                Ast.ModExpression(
                    Ast.AddExpression(
                        Ast.VariableExpression(fnScope, idxVar),
                        Ast.VariableExpression(fnScope, posVar)
                    ),
                    Ast.NumberExpression(17)
                )
            )
        ),
        Ast.NumberExpression(256)
    );

    local callbackLiteral = Ast.FunctionLiteralExpression({
        Ast.VariableExpression(callbackScope, chVar),
    }, Ast.Block({
        Ast.AssignmentStatement({
            Ast.AssignmentVariable(fnScope, posVar)
        }, {
            Ast.AddExpression(
                Ast.VariableExpression(fnScope, posVar),
                Ast.NumberExpression(1)
            )
        }),
        Ast.ReturnStatement{
            Ast.FunctionCallExpression(charExpr, {decodeByteExpr})
        }
    }, callbackScope));

	self.vmStringDecodeFunctionExpressionCache = Ast.FunctionLiteralExpression({
        Ast.VariableExpression(fnScope, idxVar),
    }, Ast.Block({
        Ast.LocalVariableDeclaration(fnScope, {pairIndexVar}, {
            Ast.SubExpression(
                Ast.MulExpression(Ast.VariableExpression(fnScope, idxVar), Ast.NumberExpression(2)),
                Ast.NumberExpression(1)
            )
        }),
        Ast.LocalVariableDeclaration(fnScope, {startVar, lenVar}, {
            Ast.IndexExpression(
                Ast.VariableExpression(self.scope, self.vmStringOffsetsVar),
                Ast.VariableExpression(fnScope, pairIndexVar)
            ),
            Ast.IndexExpression(
                Ast.VariableExpression(self.scope, self.vmStringOffsetsVar),
                Ast.AddExpression(
                    Ast.VariableExpression(fnScope, pairIndexVar),
                    Ast.NumberExpression(1)
                )
            )
        }),
        Ast.LocalVariableDeclaration(fnScope, {segmentVar}, {
            Ast.FunctionCallExpression(subExpr, {
                Ast.VariableExpression(self.scope, self.vmStringBlobVar),
                Ast.VariableExpression(fnScope, startVar),
                Ast.SubExpression(
                    Ast.AddExpression(
                        Ast.VariableExpression(fnScope, startVar),
                        Ast.VariableExpression(fnScope, lenVar)
                    ),
                    Ast.NumberExpression(1)
                )
            })
        }),
        Ast.LocalVariableDeclaration(fnScope, {posVar}, {Ast.NumberExpression(0)}),
        Ast.LocalVariableDeclaration(fnScope, {decodedVar}, {
            Ast.FunctionCallExpression(gsubExpr, {
                Ast.VariableExpression(fnScope, segmentVar),
                Ast.StringExpression("[%z\1-\255]"),
                callbackLiteral,
            })
        }),
        Ast.ReturnStatement{Ast.VariableExpression(fnScope, decodedVar)},
    }, fnScope));
    return self.vmStringDecodeFunctionExpressionCache;
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
    self.controlFlowBytecodeEntries = {};
    self.blockControlFlowEntryById = self.enableControlFlowBytecode and {} or nil;
    self.vmStringPool = {};
    self.vmStringPoolIndex = {};
    self.nextBlockPlainId = 0;
    self.controlFlowBytecodeTableExpressionCache = nil;
    self.controlFlowIndexTableExpressionCache = nil;
    self.controlFlowBlobExpressionCache = nil;
    self.controlFlowBlobOffsetsExpressionCache = nil;
    self.controlFlowBlobDecodeFunctionExpressionCache = nil;
    self.controlFlowBlobEncodedData = nil;
    self.controlFlowBlobOffsetsData = nil;
    self.vmStringBlobExpressionCache = nil;
    self.vmStringOffsetsExpressionCache = nil;
    self.vmStringDecodeFunctionExpressionCache = nil;
    self.upvalsProxyLenReturn = math.random(-2^22, 2^22);
    self.vmStringKey = math.random(37, 211);

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
    if self.enableControlFlowIndexIndirection then
        self.blockIdIndexVar = self.scope:addVariable();
    else
        self.blockIdIndexVar = nil;
    end
    if self.enableControlFlowBlobStorage then
        self.blockIdBlobOffsetsVar = self.scope:addVariable();
        self.blockIdBlobCacheVar = self.scope:addVariable();
        self.blockIdBlobDecodeVar = self.scope:addVariable();
    else
        self.blockIdBlobOffsetsVar = nil;
        self.blockIdBlobCacheVar = nil;
        self.blockIdBlobDecodeVar = nil;
    end
    self.vmStringBlobVar = self.scope:addVariable();
    self.vmStringOffsetsVar = self.scope:addVariable();
    self.vmStringDecodeVar = self.scope:addVariable();

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
            var = Ast.AssignmentVariable(self.scope, self.vmStringBlobVar),
            val = self:createVmStringBlobExpression(),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.vmStringOffsetsVar),
            val = self:createVmStringOffsetsExpression(),
        }, {
            var = Ast.AssignmentVariable(self.scope, self.vmStringDecodeVar),
            val = self:createVmStringDecodeFunctionExpression(),
        },
    }

    if self.enableControlFlowBlobStorage then
        table.insert(functionNodeAssignments, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdBytecodeVar),
            val = self:createControlFlowBlobExpression(),
        });
        table.insert(functionNodeAssignments, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdBlobOffsetsVar),
            val = self:createControlFlowBlobOffsetsExpression(),
        });
        table.insert(functionNodeAssignments, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdBlobCacheVar),
            val = Ast.TableConstructorExpression({}),
        });
        table.insert(functionNodeAssignments, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdBlobDecodeVar),
            val = self:createControlFlowBlobDecodeFunctionExpression(),
        });
    else
        table.insert(functionNodeAssignments, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdBytecodeVar),
            val = self:createControlFlowBytecodeTableExpression(),
        });
    end

    if self.enableControlFlowIndexIndirection and self.blockIdIndexVar then
        table.insert(functionNodeAssignments, {
            var = Ast.AssignmentVariable(self.scope, self.blockIdIndexVar),
            val = self:createControlFlowIndexTableExpression(),
        });
    end

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
        Ast.VariableExpression(self.scope, self.vmStringBlobVar),
        Ast.VariableExpression(self.scope, self.vmStringOffsetsVar),
        Ast.VariableExpression(self.scope, self.vmStringDecodeVar),
    };
    if self.enableControlFlowBlobStorage then
        table.insert(tbl, Ast.VariableExpression(self.scope, self.blockIdBlobOffsetsVar));
        table.insert(tbl, Ast.VariableExpression(self.scope, self.blockIdBlobCacheVar));
        table.insert(tbl, Ast.VariableExpression(self.scope, self.blockIdBlobDecodeVar));
    end
    if self.enableControlFlowIndexIndirection and self.blockIdIndexVar then
        table.insert(tbl, Ast.VariableExpression(self.scope, self.blockIdIndexVar));
    end
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
