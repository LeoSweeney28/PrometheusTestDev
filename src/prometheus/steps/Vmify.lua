-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- Vmify.lua
--
-- This Script provides a Complex Obfuscation Step that will compile the entire Script to  a fully custom bytecode that does not share it's instructions
-- with lua, making it much harder to crack than other lua obfuscators

local Step = require("prometheus.step");
local Compiler = require("prometheus.compiler.compiler");

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
        default = 0.6,
        min = 0,
        max = 1,
    },
    DispatcherNoiseStatements = {
        type = "number",
        default = 1,
        min = 0,
        max = 20,
    },
}

function Vmify:init(_) end

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