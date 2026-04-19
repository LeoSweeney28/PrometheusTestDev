-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- presets.lua
--
-- This Script provides the predefined obfuscation presets for Prometheus

return {
	-- Minifies your code. Does not obfuscate it. No performance loss.
	["Minify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {},
	},

	-- Weak obfuscation. Very readable, low performance loss.
	["Weak"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{
				Name = "Vmify",
				Settings = {
					StatementMergePasses = 2,
					EnableParallelAssignmentMerge = true,
					ShuffleBlocks = true,
					EnableStatementReorder = true,
					EnableBuiltinCapture = true,
					EnableHookGuard = false,
					GuardNoisePasses = 0,
					EnableAntiTampering = true,
					EnableBlockIdEncoding = true,
					EnableControlFlowBytecode = true,
					EnablePackedControlFlowOperands = false,
					ControlFlowBytecodeNoise = 1,
					StrictEnvironmentChecks = true,
					DispatcherStyle = "mixed",
					EqualityDispatchMaxBlocks = 12,
					DispatcherJunkBranches = 0,
					DispatcherJunkProbability = 0,
					DispatcherNoiseStatements = 0,
				},
			},
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- This is here for the tests.lua file.
	-- It helps isolate any problems with the Vmify step.
	-- It is not recommended to use this preset for obfuscation.
	-- Use the Weak, Medium, or Strong for obfuscation instead.
	["Vmify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{
				Name = "Vmify",
				Settings = {
					StatementMergePasses = 3,
					EnableParallelAssignmentMerge = true,
					ShuffleBlocks = true,
					EnableStatementReorder = true,
					EnableBuiltinCapture = true,
					EnableHookGuard = true,
					GuardNoisePasses = 1,
					EnableAntiTampering = true,
					EnableBlockIdEncoding = true,
					EnableControlFlowBytecode = true,
					EnablePackedControlFlowOperands = true,
					ControlFlowBytecodeNoise = 1,
					StrictEnvironmentChecks = true,
					DispatcherStyle = "mixed",
					EqualityDispatchMaxBlocks = 16,
					DispatcherJunkBranches = 1,
					DispatcherJunkProbability = 0.5,
					DispatcherNoiseStatements = 1,
				},
			},
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
		},
	},

	-- Medium obfuscation. Moderate obfuscation, moderate performance loss.
	["Medium"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "BooleanExpressionInversion",
				Settings = {
					Threshold = 0.35,
					InvertLiterals = true,
					InvertComparisons = true,
					InvertLogicExpressions = true,
				},
			},
			{
				Name = "FunctionParameterShuffle",
				Settings = {
					Threshold = 0.15,
					MinArgs = 2,
					MaxArgs = 8,
					PreserveFirstArgument = true,
					MaxShuffleAttempts = 6,
					SkipMemberFunctionDeclarations = true,
				},
			},
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
					MaxIntegrityChecks = 72,
					RandomizeErrorMessage = true,
				},
			},
			{
				Name = "IndirectFunctionCalls",
				Settings = {
					Threshold = 0.25,
					IncludeStatements = true,
					IncludeExpressions = true,
					IncludePassSelf = true,
					IndirectionLayers = 1,
					NonConstantIndex = true,
				},
			},
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 0.2,
					NestingDepth = 1,
					IncludeElseNoise = true,
					WrapControlFlow = true,
					PredicateComplexity = 2,
				},
			},
			{
				Name = "Vmify",
				Settings = {
					StatementMergePasses = 3,
					EnableParallelAssignmentMerge = true,
					ShuffleBlocks = true,
					EnableStatementReorder = true,
					EnableBuiltinCapture = true,
					EnableHookGuard = true,
					GuardNoisePasses = 1,
					EnableAntiTampering = true,
					EnableBlockIdEncoding = true,
					EnableControlFlowBytecode = true,
					EnablePackedControlFlowOperands = true,
					ControlFlowBytecodeNoise = 2,
					StrictEnvironmentChecks = true,
					DispatcherStyle = "mixed",
					EqualityDispatchMaxBlocks = 14,
					DispatcherJunkBranches = 1,
					DispatcherJunkProbability = 0.55,
					DispatcherNoiseStatements = 1,
				},
			},
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperTreshold = 1,
					LocalWrapperCount = 1,
					LazyDecode = false,
				},
			},
			{
				Name = "NumbersToExpressions",
				Settings = {
					Threshold = 1,
					ExpressionMode = "compact",
					NumberRepresentationMutation = false,
					AllowedNumberRepresentations = {"normal"},
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- Strong obfuscation, high performance loss.
	["Strong"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{
				Name = "BooleanExpressionInversion",
				Settings = {
					Threshold = 0.7,
					InvertLiterals = true,
					InvertComparisons = true,
					InvertLogicExpressions = true,
				},
			},
			{
				Name = "FunctionParameterShuffle",
				Settings = {
					Threshold = 0.35,
					MinArgs = 2,
					MaxArgs = 10,
					PreserveFirstArgument = true,
					MaxShuffleAttempts = 8,
					SkipMemberFunctionDeclarations = true,
				},
			},
			{
				Name = "IndirectFunctionCalls",
				Settings = {
					Threshold = 0.65,
					IncludeStatements = true,
					IncludeExpressions = true,
					IncludePassSelf = true,
					IndirectionLayers = 2,
					NonConstantIndex = true,
				},
			},
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 0.5,
					NestingDepth = 2,
					IncludeElseNoise = true,
					WrapControlFlow = false,
					PredicateComplexity = 3,
				},
			},
			{
				Name = "Vmify",
				Settings = {
					StatementMergePasses = 4,
					EnableParallelAssignmentMerge = true,
					ShuffleBlocks = true,
					EnableStatementReorder = true,
					EnableBuiltinCapture = true,
					EnableHookGuard = true,
					GuardNoisePasses = 2,
					EnableAntiTampering = true,
					EnableBlockIdEncoding = true,
					EnableControlFlowBytecode = true,
					EnablePackedControlFlowOperands = true,
					ControlFlowBytecodeNoise = 2,
					StrictEnvironmentChecks = true,
					DispatcherStyle = "mixed",
					EqualityDispatchMaxBlocks = 10,
					DispatcherJunkBranches = 2,
					DispatcherJunkProbability = 0.65,
					DispatcherNoiseStatements = 2,
				},
			},
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
					MaxIntegrityChecks = 120,
					RandomizeErrorMessage = true,
				},
			},
			{
				Name = "Vmify",
				Settings = {
					StatementMergePasses = 5,
					EnableParallelAssignmentMerge = true,
					ShuffleBlocks = true,
					EnableStatementReorder = true,
					EnableBuiltinCapture = true,
					EnableHookGuard = true,
					GuardNoisePasses = 2,
					EnableAntiTampering = true,
					EnableBlockIdEncoding = true,
					EnableControlFlowBytecode = true,
					EnablePackedControlFlowOperands = true,
					ControlFlowBytecodeNoise = 3,
					StrictEnvironmentChecks = true,
					DispatcherStyle = "mixed",
					EqualityDispatchMaxBlocks = 8,
					DispatcherJunkBranches = 2,
					DispatcherJunkProbability = 0.7,
					DispatcherNoiseStatements = 3,
				},
			},
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperTreshold = 1,
					LocalWrapperCount = 1,
					LazyDecode = false,
				},
			},
			{
				Name = "NumbersToExpressions",
				Settings = {
					Threshold = 1,
					ExpressionMode = "compact",
					NumberRepresentationMutation = false,
					AllowedNumberRepresentations = {"normal"},
				},
			},

			{ Name = "WrapInFunction", Settings = {} },
		},
	},
}
