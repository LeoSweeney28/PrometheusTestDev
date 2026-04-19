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
        repeat
            plainId = math.random(0, 2^24)
        until not self.usedBlockIds[plainId];
        self.usedBlockIds[plainId] = true;

        local id = self:encodeBlockId(plainId);

        if self.enableControlFlowBytecode then
            local noiseCount = math.random(0, self.controlFlowBytecodeNoise or 0);
            for _ = 1, noiseCount do
                if self.enablePackedControlFlowOperands then
                    self.blockIdValues[#self.blockIdValues + 1] = self:encodePackedControlFlowEntry(math.random(2^12, 2^20));
                else
                    self.blockIdValues[#self.blockIdValues + 1] = math.random(2^22, 2^27);
                end
            end

            local slot = #self.blockIdValues + 1;
            self.blockIdValues[slot] = self:encodeControlFlowEntry(id);
            self.blockIdSlots[id] = slot;
        end

        local scope = Scope:new(self.containerFuncScope);
        local block = {
            id = id;
            plainId = plainId;
            bytecodeSlot = self.blockIdSlots[id];
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

