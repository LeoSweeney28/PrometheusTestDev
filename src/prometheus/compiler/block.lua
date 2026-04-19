-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- block.lua
--
-- Block management for the compiler

local Scope = require("prometheus.scope");
local util = require("prometheus.util");

local lookupify = util.lookupify;

return function(Compiler)
    function Compiler:createBlock()
        local plainId;
        if self.optimizeVM then
            plainId = (self.nextBlockPlainId or 0) + 1;
            self.nextBlockPlainId = plainId;
        else
            repeat
                plainId = math.random(0, 2^24)
            until not self.usedBlockIds[plainId];
            self.usedBlockIds[plainId] = true;
        end

        local id = self:encodeBlockId(plainId);

        if self.enableControlFlowBytecode then
            local noiseCount = self.optimizeVM and 0 or math.random(0, self.controlFlowBytecodeNoise or 0);
            if noiseCount > 0 then
                for _ = 1, noiseCount do
                    local noiseSlot = #self.controlFlowBytecodeEntries + 1;
                    local noiseValue;
                    if self.enablePackedControlFlowOperands then
                        noiseValue = self:encodePackedControlFlowEntry(math.random(2^12, 2^20));
                    else
                        noiseValue = math.random(2^22, 2^27);
                    end
                    local noiseEntry = {
                        value = self:obfuscateControlFlowStorageValue(noiseValue),
                        slot = noiseSlot,
                        payloadSlot = self:encodeControlFlowPayloadSlot(noiseSlot),
                    };
                    noiseEntry.lookupSlot = self:encodeControlFlowLookupSlot(noiseSlot);
                    self.controlFlowBytecodeEntries[noiseSlot] = noiseEntry;
                end
            end

            local slot = #self.controlFlowBytecodeEntries + 1;
            local entry = {
                value = self:obfuscateControlFlowStorageValue(self:encodeControlFlowEntry(id)),
                slot = slot,
                payloadSlot = self:encodeControlFlowPayloadSlot(slot),
            };
            self.controlFlowBytecodeEntries[slot] = entry;

            if self.enableControlFlowSlotAliasing then
                local aliasSlot;
                if self.optimizeVM then
                    local modulus = self.dispatchIdModulus or (2^24);
                    aliasSlot = ((slot * (self.dispatchIdStride or 1)) + (self.dispatchIdSalt or 0)) % modulus + 1;
                else
                    aliasSlot = slot + (self.controlFlowAliasOffset or 0);
                end
                entry.aliasSlot = aliasSlot;
            end
            local lookupBase = slot;
            if self.enableControlFlowIndexIndirection then
                lookupBase = entry.aliasSlot or slot;
            end
            entry.lookupSlot = self:encodeControlFlowLookupSlot(lookupBase);
            self.blockControlFlowEntryById[id] = entry;
        end

        local scope = Scope:new(self.containerFuncScope);
        local block = {
            id = id;
            plainId = plainId;
            statements = {};
            scope = scope;
            advanceToNextBlock = true;
        };
        table.insert(self.blocks, block);
        return block;
    end

    function Compiler:setActiveBlock(block)
        self.activeBlock = block;
    end

    function Compiler:addStatement(statement, writes, reads, usesUpvals)
        if(self.activeBlock.advanceToNextBlock) then
            table.insert(self.activeBlock.statements, {
                statement = statement,
                writes = lookupify(writes),
                reads = lookupify(reads),
                usesUpvals = usesUpvals or false,
            });
        end
    end
end

