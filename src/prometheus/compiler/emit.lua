-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- emit.lua
--
-- This Script contains the container function body emission for the compiler.

local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local util = require("prometheus.util");
local constants = require("prometheus.compiler.constants");
local AstKind = Ast.AstKind;

local MAX_REGS = constants.MAX_REGS;

return function(Compiler)
    local function hasAnyEntries(tbl)
        return type(tbl) == "table" and next(tbl) ~= nil;
    end

    local function unionLookupTables(a, b)
        local out = {};
        for k, v in pairs(a or {}) do
            out[k] = v;
        end
        for k, v in pairs(b or {}) do
            out[k] = v;
        end
        return out;
    end

    local function canMergeParallelAssignmentStatements(statA, statB)
        if type(statA) ~= "table" or type(statB) ~= "table" then
            return false;
        end

        if statA.usesUpvals or statB.usesUpvals then
            return false;
        end

        local a = statA.statement;
        local b = statB.statement;
        if type(a) ~= "table" or type(b) ~= "table" then
            return false;
        end
        if a.kind ~= AstKind.AssignmentStatement or b.kind ~= AstKind.AssignmentStatement then
            return false;
        end

        if type(a.lhs) ~= "table" or type(a.rhs) ~= "table" or type(b.lhs) ~= "table" or type(b.rhs) ~= "table" then
            return false;
        end

        if #a.lhs ~= #a.rhs or #b.lhs ~= #b.rhs then
            return false;
        end

        -- Avoid merging vararg/call assignments because they can affect multi-return behavior.
        local function hasUnsafeRhs(rhsList)
            for _, rhsExpr in ipairs(rhsList) do
                if type(rhsExpr) ~= "table" then
                    return true;
                end
                local kind = rhsExpr.kind;
                if kind == AstKind.FunctionCallExpression or kind == AstKind.PassSelfFunctionCallExpression or kind == AstKind.VarargExpression then
                    return true;
                end
            end
            return false;
        end
        if hasUnsafeRhs(a.rhs) or hasUnsafeRhs(b.rhs) then
            return false;
        end

        local aReads = type(statA.reads) == "table" and statA.reads or {};
        local aWrites = type(statA.writes) == "table" and statA.writes or {};
        local bReads = type(statB.reads) == "table" and statB.reads or {};
        local bWrites = type(statB.writes) == "table" and statB.writes or {};

        -- Allow merging even if one statement has no writes (e.g., x = o(x) style assignments)
        -- Only require that at least one of them has writes
        if not hasAnyEntries(aWrites) and not hasAnyEntries(bWrites) then
            return false;
        end

        for r in pairs(aReads) do
            if bWrites[r] then
                return false;
            end
        end

        for r, b in pairs(aWrites) do
            if bWrites[r] or bReads[r] then
                return false;
            end
        end

        return true;
    end

    local function mergeParallelAssignmentStatements(statA, statB)
        local lhs = {};
        local rhs = {};
        local aLhs, bLhs = statA.statement.lhs, statB.statement.lhs;
        local aRhs, bRhs = statA.statement.rhs, statB.statement.rhs;
        for i = 1, #aLhs do lhs[i] = aLhs[i]; end
        for i = 1, #bLhs do lhs[#aLhs + i] = bLhs[i]; end
        for i = 1, #aRhs do rhs[i] = aRhs[i]; end
        for i = 1, #bRhs do rhs[#aRhs + i] = bRhs[i]; end

        return {
            statement = Ast.AssignmentStatement(lhs, rhs),
            writes = unionLookupTables(statA.writes, statB.writes),
            reads = unionLookupTables(statA.reads, statB.reads),
            usesUpvals = statA.usesUpvals or statB.usesUpvals,
        };
    end

    local function mergeAdjacentParallelAssignments(blockstats)
        local merged = {};
        local changed = false;
        local i = 1;
        while i <= #blockstats do
            local stat = blockstats[i];
            i = i + 1;

            while i <= #blockstats and canMergeParallelAssignmentStatements(stat, blockstats[i]) do
                stat = mergeParallelAssignmentStatements(stat, blockstats[i]);
                i = i + 1;
                changed = true;
            end

            table.insert(merged, stat);
        end
        return merged, changed;
    end

    function Compiler:emitContainerFuncBody()
        local blocks = {};

        util.shuffle(self.blocks);

        for i, block in ipairs(self.blocks) do
            local id = block.id;
            local blockstats = block.statements;

            for i = 2, #blockstats do
                local stat = blockstats[i];
                local reads = stat.reads;
                local writes = stat.writes;
                local maxShift = 0;
                local usesUpvals = stat.usesUpvals;
                for shift = 1, i - 1 do
                    local stat2 = blockstats[i - shift];

                    if stat2.usesUpvals and usesUpvals then
                        break;
                    end

                    local reads2 = stat2.reads;
                    local writes2 = stat2.writes;
                    local f = true;

                    for r, b in pairs(reads2) do
                        if(writes[r]) then
                            f = false;
                            break;
                        end
                    end

                    if f then
                        for r, b in pairs(writes2) do
                            if(writes[r]) then
                                f = false;
                                break;
                            end
                            if(reads[r]) then
                                f = false;
                                break;
                            end
                        end
                    end

                    if not f then
                        break
                    end

                    maxShift = shift;
                end

                local shift = math.random(0, maxShift);
                for j = 1, shift do
                    blockstats[i - j], blockstats[i - j + 1] = blockstats[i - j + 1], blockstats[i - j];
                end
            end

            local mergedBlockStats, changed = mergeAdjacentParallelAssignments(blockstats);
            -- Continue collapsing only while there is progress to avoid redundant passes.
            while changed do
                mergedBlockStats, changed = mergeAdjacentParallelAssignments(mergedBlockStats);
            end

            blockstats = {};
            for _, stat in ipairs(mergedBlockStats) do
                table.insert(blockstats, stat.statement);
            end

            local block = { id = id, index = i, block = Ast.Block(blockstats, block.scope) }
            table.insert(blocks, block);
            blocks[id] = block;
        end

        table.sort(blocks, function(a, b) return a.id < b.id end);

        local function buildDirectIdChain(list, parentScope)
            local chainScope = Scope:new(parentScope);
            if #list == 0 then
                local emptyFailScope = Scope:new(chainScope);
                emptyFailScope:addReferenceToHigherScope(self.scope, self.assertVar);
                return Ast.Block({
                    Ast.FunctionCallStatement(
                        Ast.VariableExpression(self.scope, self.assertVar),
                        { Ast.BooleanExpression(false), Ast.StringExpression("VM bucket dispatch failed") }
                    );
                }, emptyFailScope);
            end

            local shuffled = {};
            for i, block in ipairs(list) do
                shuffled[i] = block;
            end
            util.shuffle(shuffled);

            local first = shuffled[1];
            first.block.scope:setParent(chainScope);

            local elseifs = {};
            for i = 2, #shuffled do
                local block = shuffled[i];
                block.block.scope:setParent(chainScope);
                elseifs[#elseifs + 1] = {
                    condition = Ast.EqualsExpression(self:pos(chainScope), Ast.NumberExpression(block.id)),
                    body = block.block
                };
            end

            local missScope = Scope:new(chainScope);
            missScope:addReferenceToHigherScope(self.scope, self.assertVar);
            local elseBlock = Ast.Block({
                Ast.FunctionCallStatement(
                    Ast.VariableExpression(self.scope, self.assertVar),
                    { Ast.BooleanExpression(false), Ast.StringExpression("VM dispatch lookup failed") }
                );
            }, missScope);

            return Ast.Block({
                Ast.IfStatement(
                    Ast.EqualsExpression(self:pos(chainScope), Ast.NumberExpression(first.id)),
                    first.block,
                    elseifs,
                    elseBlock
                );
            }, chainScope);
        end

        -- Build a bucketed dispatcher so control flow is not a single flat chain.
        local function buildBucketedDispatcher(tb, pScope, bucketVar, bucketCount, salt)
            local bucketScope = Scope:new(pScope);
            bucketScope:addReferenceToHigherScope(self.containerFuncScope, bucketVar);
            local buckets = {};
            for i = 1, bucketCount do
                buckets[i] = {};
            end

            for _, block in ipairs(tb) do
                local b = ((block.id + salt) % bucketCount) + 1;
                table.insert(buckets[b], block);
            end

            local firstBucketBody = buildDirectIdChain(buckets[1], bucketScope);
            local elseifs = {};
            for i = 2, bucketCount do
                elseifs[#elseifs + 1] = {
                    condition = Ast.EqualsExpression(Ast.VariableExpression(self.containerFuncScope, bucketVar), Ast.NumberExpression(i)),
                    body = buildDirectIdChain(buckets[i], bucketScope),
                };
            end

            local failScope = Scope:new(bucketScope);
            failScope:addReferenceToHigherScope(self.scope, self.assertVar);
            local elseBlock = Ast.Block({
                Ast.FunctionCallStatement(
                    Ast.VariableExpression(self.scope, self.assertVar),
                    { Ast.BooleanExpression(false), Ast.StringExpression("VM bucket selector failed") }
                );
            }, failScope);

            return Ast.Block({
                Ast.IfStatement(
                    Ast.EqualsExpression(Ast.VariableExpression(self.containerFuncScope, bucketVar), Ast.NumberExpression(1)),
                    firstBucketBody,
                    elseifs,
                    elseBlock
                );
            }, bucketScope);
        end

        local bucketCount = math.max(3, math.min(11, math.floor(math.sqrt(#blocks)) + 1));
        local bucketSalt = math.random(7, 97);
        local altBucketCount = math.max(3, math.min(13, bucketCount + 2));
        local altBucketSalt = math.random(101, 211);
        local bucketVar = self.containerFuncScope:addVariable();
        local altBucketVar = self.containerFuncScope:addVariable();
        local dispatchModeVar = self.containerFuncScope:addVariable();
        local primaryWhileBody = buildBucketedDispatcher(blocks, self.containerFuncScope, bucketVar, bucketCount, bucketSalt);
        local alternateWhileBody = buildBucketedDispatcher(blocks, self.containerFuncScope, altBucketVar, altBucketCount, altBucketSalt);
        if self.whileScope then
            -- Ensure whileScope is properly connected
            self.whileScope:setParent(self.containerFuncScope);
        end

        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar, 1);
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);

        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.unpackVar);
        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.typeVar);
        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.assertVar);

        local vmPosTypeVar = self.containerFuncScope:addVariable();

        local declarations = {
            self.returnVar,
            bucketVar,
            altBucketVar,
            dispatchModeVar,
        }

        for i, var in pairs(self.registerVars) do
            if(i ~= MAX_REGS) then
                table.insert(declarations, var);
            end
        end

        local stats = {}

        if self.maxUsedRegister >= MAX_REGS then
            table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, {self.registerVars[MAX_REGS]}, {Ast.TableConstructorExpression({})}));
        end

        table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, util.shuffle(declarations), {}));
        table.insert(stats, Ast.FunctionCallStatement(
            Ast.VariableExpression(self.scope, self.assertVar),
            {
                Ast.AndExpression(
                    Ast.EqualsExpression(Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.typeVar), {Ast.VariableExpression(self.scope, self.unpackVar)}), Ast.StringExpression("function")),
                    Ast.AndExpression(
                        Ast.EqualsExpression(Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.typeVar), {Ast.VariableExpression(self.scope, self.typeVar)}), Ast.StringExpression("function")),
                        Ast.EqualsExpression(Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.typeVar), {Ast.VariableExpression(self.scope, self.assertVar)}), Ast.StringExpression("function"))
                    )
                ),
                Ast.StringExpression("VM bootstrap integrity check failed")
            }
        ));

        table.insert(stats, Ast.WhileStatement(Ast.Block({
            Ast.AssignmentStatement({
                Ast.AssignmentVariable(self.containerFuncScope, vmPosTypeVar),
            }, {
                Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.typeVar), {
                    Ast.VariableExpression(self.containerFuncScope, self.posVar),
                }),
            });
            Ast.FunctionCallStatement(
                Ast.VariableExpression(self.scope, self.assertVar),
                {
                    Ast.AndExpression(
                        Ast.EqualsExpression(Ast.VariableExpression(self.containerFuncScope, vmPosTypeVar), Ast.StringExpression("number")),
                        Ast.EqualsExpression(
                            Ast.VariableExpression(self.containerFuncScope, self.posVar),
                            Ast.VariableExpression(self.containerFuncScope, self.posVar)
                        )
                    ),
                    Ast.StringExpression("VM state integrity check failed")
                }
            );
            Ast.AssignmentStatement({
                Ast.AssignmentVariable(self.containerFuncScope, bucketVar),
            }, {
                Ast.AddExpression(
                    Ast.ModExpression(
                        Ast.AddExpression(
                            Ast.VariableExpression(self.containerFuncScope, self.posVar),
                            Ast.NumberExpression(bucketSalt)
                        ),
                        Ast.NumberExpression(bucketCount)
                    ),
                    Ast.NumberExpression(1)
                )
            });
            Ast.AssignmentStatement({
                Ast.AssignmentVariable(self.containerFuncScope, altBucketVar),
            }, {
                Ast.AddExpression(
                    Ast.ModExpression(
                        Ast.AddExpression(
                            Ast.VariableExpression(self.containerFuncScope, self.posVar),
                            Ast.NumberExpression(altBucketSalt)
                        ),
                        Ast.NumberExpression(altBucketCount)
                    ),
                    Ast.NumberExpression(1)
                )
            });
            Ast.AssignmentStatement({
                Ast.AssignmentVariable(self.containerFuncScope, dispatchModeVar),
            }, {
                Ast.AddExpression(
                    Ast.ModExpression(
                        Ast.AddExpression(
                            Ast.VariableExpression(self.containerFuncScope, self.posVar),
                            Ast.NumberExpression(bucketSalt + altBucketSalt)
                        ),
                        Ast.NumberExpression(2)
                    ),
                    Ast.NumberExpression(1)
                )
            });
            Ast.IfStatement(
                Ast.EqualsExpression(Ast.VariableExpression(self.containerFuncScope, dispatchModeVar), Ast.NumberExpression(1)),
                Ast.Block({ Ast.DoStatement(primaryWhileBody); }, Scope:new(self.containerFuncScope)),
                {},
                Ast.Block({ Ast.DoStatement(alternateWhileBody); }, Scope:new(self.containerFuncScope))
            );
        }, self.containerFuncScope), Ast.VariableExpression(self.containerFuncScope, self.posVar)));


        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
        }, {
            Ast.LenExpression(Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar))
        }));

        table.insert(stats, Ast.ReturnStatement{
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {
                Ast.VariableExpression(self.containerFuncScope, self.returnVar)
            });
        });

        return Ast.Block(stats, self.containerFuncScope);
    end
end
