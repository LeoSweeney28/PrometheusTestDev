-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- Vmify.lua
--
-- This Script provides a Complex Obfuscation Step that will compile the entire Script to  a fully custom bytecode that does not share it's instructions
-- with lua, making it much harder to crack than other lua obfuscators

local Step = require("prometheus.step");
local Compiler = require("prometheus.compiler.compiler");
local logger = require("logger");

local Vmify = Step:extend();
Vmify.Description = "This Step will Compile your script into a fully-custom (not a half custom like other lua obfuscators) Bytecode Format and emit a vm for executing it.";
Vmify.Name = "Vmify";

Vmify.SettingsDescriptor = {
    StatementMergePasses = {
        type = "number",
        default = 4,
        min = 0,
        max = 12,
    },
    EnableParallelAssignmentMerge = {
        type = "boolean",
        default = true,
    },
    ShuffleBlocks = {
        type = "boolean",
        default = true,
    },
    EnableStatementReorder = {
        type = "boolean",
        default = true,
    },
    EnableBuiltinCapture = {
        type = "boolean",
        default = true,
    },
    EnableHookGuard = {
        type = "boolean",
        default = true,
    },
    GuardNoisePasses = {
        type = "number",
        default = 1,
        min = 0,
        max = 10,
    },
    EnableAntiTampering = {
        type = "boolean",
        default = true,
    },
    EnableBlockIdEncoding = {
        type = "boolean",
        default = true,
    },
    EnableControlFlowBytecode = {
        type = "boolean",
        default = true,
    },
    EnablePackedControlFlowOperands = {
        type = "boolean",
        default = true,
    },
    EnableControlFlowSlotAliasing = {
        type = "boolean",
        default = false,
    },
    EnableControlFlowIndexIndirection = {
        type = "boolean",
        default = false,
    },
    EnableControlFlowPayloadPermutation = {
        type = "boolean",
        default = false,
    },
    EnableControlFlowBlobStorage = {
        type = "boolean",
        default = false,
    },
    ControlFlowBlobPageSize = {
        type = "number",
        default = 24,
        min = 4,
        max = 128,
    },
    ControlFlowBlobCacheSize = {
        type = "number",
        default = 12,
        min = 1,
        max = 256,
    },
    EnableVmStringEncoding = {
        type = "boolean",
        default = false,
    },
    OptimizeVM = {
        type = "boolean",
        default = false,
    },
    AdaptiveDifficulty = {
        type = "boolean",
        default = false,
    },
    JitResistantControlFlow = {
        type = "boolean",
        default = false,
    },
    EnableEntropyInjection = {
        type = "boolean",
        default = false,
    },
    VmStringChunkSize = {
        type = "number",
        default = 24,
        min = 8,
        max = 64,
    },
    ControlFlowBytecodeNoise = {
        type = "number",
        default = 1,
        min = 0,
        max = 8,
    },
    StrictEnvironmentChecks = {
        type = "boolean",
        default = true,
    },
    DispatcherStyle = {
        type = "enum",
        default = "mixed",
        values = {"mixed", "binary", "equals"},
    },
    EqualityDispatchMaxBlocks = {
        type = "number",
        default = 16,
        min = 2,
        max = 128,
    },
    DispatcherJunkBranches = {
        type = "number",
        default = 0,
        min = 0,
        max = 8,
    },
    DispatcherJunkProbability = {
        type = "number",
        default = 0,
        min = 0,
        max = 1,
    },
    DispatcherNoiseStatements = {
        type = "number",
        default = 0,
        min = 0,
        max = 20,
    },
}

function Vmify:init(_)
    if not self.EnableControlFlowBytecode then
        if self.EnablePackedControlFlowOperands then
            logger:warn("Vmify: EnablePackedControlFlowOperands requires EnableControlFlowBytecode; disabling packed operands.");
            self.EnablePackedControlFlowOperands = false;
        end
        if self.EnableControlFlowSlotAliasing then
            logger:warn("Vmify: EnableControlFlowSlotAliasing requires EnableControlFlowBytecode; disabling slot aliasing.");
            self.EnableControlFlowSlotAliasing = false;
        end
        if self.EnableControlFlowIndexIndirection then
            logger:warn("Vmify: EnableControlFlowIndexIndirection requires EnableControlFlowBytecode; disabling index indirection.");
            self.EnableControlFlowIndexIndirection = false;
        end
        if self.EnableControlFlowPayloadPermutation then
            logger:warn("Vmify: EnableControlFlowPayloadPermutation requires EnableControlFlowBytecode; disabling payload permutation.");
            self.EnableControlFlowPayloadPermutation = false;
        end
        self.ControlFlowBytecodeNoise = 0;
    end

    if self.EnableControlFlowPayloadPermutation and not self.EnableControlFlowIndexIndirection then
        logger:warn("Vmify: EnableControlFlowPayloadPermutation requires EnableControlFlowIndexIndirection; enabling index indirection.");
        self.EnableControlFlowIndexIndirection = true;
    end

    if self.EnableControlFlowBlobStorage then
        if not self.EnableControlFlowBytecode then
            logger:warn("Vmify: EnableControlFlowBlobStorage requires EnableControlFlowBytecode; disabling blob storage.");
            self.EnableControlFlowBlobStorage = false;
        else
            if not self.EnableControlFlowIndexIndirection then
                logger:warn("Vmify: EnableControlFlowBlobStorage requires EnableControlFlowIndexIndirection; enabling index indirection.");
                self.EnableControlFlowIndexIndirection = true;
            end
            if self.OptimizeVM and not self.EnableControlFlowPayloadPermutation then
                logger:warn("Vmify: OptimizeVM + EnableControlFlowBlobStorage works best with EnableControlFlowPayloadPermutation; enabling payload permutation.");
                self.EnableControlFlowPayloadPermutation = true;
            end
        end
    end

    if self.EnableControlFlowBlobStorage then
        logger:warn("Vmify: EnableControlFlowBlobStorage is temporarily disabled due runtime stability issues; falling back to table storage.");
        self.EnableControlFlowBlobStorage = false;
    end

    if self.OptimizeVM then
        if self.ControlFlowBytecodeNoise ~= 0 then
            self.ControlFlowBytecodeNoise = 0;
        end
        if self.DispatcherJunkBranches ~= 0 then
            self.DispatcherJunkBranches = 0;
        end
        if self.DispatcherJunkProbability ~= 0 then
            self.DispatcherJunkProbability = 0;
        end
        if self.DispatcherNoiseStatements ~= 0 then
            self.DispatcherNoiseStatements = 0;
        end
    end
end

function Vmify:apply(ast)
    -- Create Compiler
    local compiler = Compiler:new({
        statementMergePasses = math.floor(self.StatementMergePasses),
        enableParallelAssignmentMerge = self.EnableParallelAssignmentMerge,
        shuffleBlocks = self.ShuffleBlocks,
        enableStatementReorder = self.EnableStatementReorder,
        enableBuiltinCapture = self.EnableBuiltinCapture,
        enableHookGuard = self.EnableHookGuard,
        guardNoisePasses = math.floor(self.GuardNoisePasses),
        enableAntiTampering = self.EnableAntiTampering,
        enableBlockIdEncoding = self.EnableBlockIdEncoding,
        enableControlFlowBytecode = self.EnableControlFlowBytecode,
        enablePackedControlFlowOperands = self.EnablePackedControlFlowOperands,
        enableControlFlowSlotAliasing = self.EnableControlFlowSlotAliasing,
        enableControlFlowIndexIndirection = self.EnableControlFlowIndexIndirection,
        enableControlFlowPayloadPermutation = self.EnableControlFlowPayloadPermutation,
        enableControlFlowBlobStorage = self.EnableControlFlowBlobStorage,
        controlFlowBlobPageSize = math.floor(self.ControlFlowBlobPageSize),
        controlFlowBlobCacheSize = math.floor(self.ControlFlowBlobCacheSize),
        enableVmStringEncoding = self.EnableVmStringEncoding,
        optimizeVM = self.OptimizeVM,
        adaptiveDifficulty = self.AdaptiveDifficulty,
        jitResistantControlFlow = self.JitResistantControlFlow,
        enableEntropyInjection = self.EnableEntropyInjection,
        vmStringChunkSize = math.floor(self.VmStringChunkSize),
        controlFlowBytecodeNoise = math.floor(self.ControlFlowBytecodeNoise),
        strictEnvironmentChecks = self.StrictEnvironmentChecks,
        dispatcherStyle = self.DispatcherStyle,
        equalityDispatchMaxBlocks = math.floor(self.EqualityDispatchMaxBlocks),
        dispatcherJunkBranches = math.floor(self.DispatcherJunkBranches),
        dispatcherJunkProbability = self.DispatcherJunkProbability,
        dispatcherNoiseStatements = math.floor(self.DispatcherNoiseStatements),
    });

    -- Compile the Script into a bytecode vm
    return compiler:compile(ast);
end

return Vmify;