-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- pipeline.lua
--
-- This Script provides a configurable obfuscation pipeline that can obfuscate code using different modules
-- These modules can simply be added to the pipeline.

local Enums = require("prometheus.enums");
local util = require("prometheus.util");
local Parser = require("prometheus.parser");
local Unparser = require("prometheus.unparser");
local logger = require("logger");
local Validator = require("prometheus.validator");

local NameGenerators = require("prometheus.namegenerators");

local Steps = require("prometheus.steps");
local LuaVersion = Enums.LuaVersion;

-- Performance modules (Overhaul #4)
local Cache = require("prometheus.cache");
local Profiler = require("prometheus.profiler");
local Allocator = require("prometheus.allocator");

-- On Windows, os.clock can be used. On other systems, os.time must be used for benchmarking.
local isWindows = package and package.config and type(package.config) == "string" and package.config:sub(1,1) == "\\";
local function gettime()
	if isWindows then
		return os.clock();
	else
		return os.time();
	end
end

local Pipeline = {
	NameGenerators = NameGenerators;
	Steps = Steps;
	DefaultSettings = {
		LuaVersion = LuaVersion.LuaU; -- The Lua Version to use for the Tokenizer, Parser and Unparser
		PrettyPrint = false; -- Note that Pretty Print is currently not producing Pretty results
		Seed = 0; -- The Seed. 0 or below uses the current time as a seed
		VarNamePrefix = ""; -- The Prefix that every variable will start with
	}
}


function Pipeline:new(settings)
	local luaVersion = settings.luaVersion or settings.LuaVersion or Pipeline.DefaultSettings.LuaVersion;
	local conventions = Enums.Conventions[luaVersion];
	if(not conventions) then
		logger:error("The Lua Version \"" .. luaVersion
			.. "\" is not recognized by the Tokenizer! Please use one of the following: \"" .. table.concat(util.keys(Enums.Conventions), "\",\"") .. "\"");
	end

	local prettyPrint = settings.PrettyPrint or Pipeline.DefaultSettings.PrettyPrint;
	local prefix = settings.VarNamePrefix or Pipeline.DefaultSettings.VarNamePrefix;
	local seed = settings.Seed or 0;

	local pipeline = {
		LuaVersion = luaVersion;
		PrettyPrint = prettyPrint;
		VarNamePrefix = prefix;
		Seed = seed;
		parser = Parser:new({
			LuaVersion = luaVersion;
		});
		unparser = Unparser:new({
			LuaVersion = luaVersion;
			PrettyPrint = prettyPrint;
			Highlight = settings.Highlight;
		});
		namegenerator = Pipeline.NameGenerators.MangledShuffled;
		conventions = conventions;
		steps = {};
		-- Performance optimization (Overhaul #4)
		cache = Cache:new(settings.CacheSize or 1000);
		profiler = Profiler:new();
		validatorPool = nil; -- Lazy-init in apply()
		enableCaching = settings.EnableCaching ~= false; -- Default true
		enableProfiling = settings.EnableProfiling ~= false; -- Default true
		enableValidatorPooling = settings.EnableValidatorPooling ~= false; -- Default true
	}

	setmetatable(pipeline, self);
	self.__index = self;

	return pipeline;
end

function Pipeline:fromConfig(config)
	config = config or {};
	local pipeline = Pipeline:new({
		LuaVersion = config.LuaVersion or LuaVersion.Lua51;
		PrettyPrint = config.PrettyPrint or false;
		VarNamePrefix = config.VarNamePrefix or "";
		Seed = config.Seed or 0;
	});

	pipeline:setNameGenerator(config.NameGenerator or "MangledShuffled")

	-- Add all Steps defined in Config
	local steps = config.Steps or {};
	for i, step in ipairs(steps) do
		if type(step.Name) ~= "string" then
			logger:error("Step.Name must be a String");
		end
		local constructor = pipeline.Steps[step.Name];
		if not constructor then
			logger:error(string.format("The Step \"%s\" was not found!", step.Name));
		end
		pipeline:addStep(constructor:new(step.Settings or {}));
	end

	return pipeline;
end

function Pipeline:addStep(step)
	table.insert(self.steps, step);
end

function Pipeline:resetSteps(_)
	self.steps = {};
end

function Pipeline:getSteps()
	return self.steps;
end

function Pipeline:setOption(name, _)
	assert(false, "TODO");
	if(Pipeline.DefaultSettings[name] ~= nil) then

	else
		logger:error(string.format("\"%s\" is not a valid setting"));
	end
end

function Pipeline:setLuaVersion(luaVersion)
	local conventions = Enums.Conventions[luaVersion];
	if(not conventions) then
		logger:error("The Lua Version \"" .. luaVersion
			.. "\" is not recognized by the Tokenizer! Please use one of the following: \"" .. table.concat(util.keys(Enums.Conventions), "\",\"") .. "\"");
	end

	self.parser = Parser:new({
		LuaVersion = luaVersion;
	});
	self.unparser = Unparser:new({
		LuaVersion = luaVersion;
	});
	self.LuaVersion = luaVersion;
	self.conventions = conventions;
end

function Pipeline:getLuaVersion()
	return self.LuaVersion;
end

function Pipeline:setNameGenerator(nameGenerator)
	if(type(nameGenerator) == "string") then
		nameGenerator = Pipeline.NameGenerators[nameGenerator];
	end

	if(type(nameGenerator) == "function" or type(nameGenerator) == "table") then
		self.namegenerator = nameGenerator;
		return;
	else
		logger:error("The Argument to Pipeline:setNameGenerator must be a valid NameGenerator function or function name e.g: \"mangled\"")
	end
end

function Pipeline:apply(code, filename)
	local startTime = gettime();
	filename = filename or "Anonymous Script";
	logger:info(string.format("Applying Obfuscation Pipeline to %s ...", filename));

	-- Initialize profiler section
	if self.enableProfiling then
		self.profiler:startSection("total");
	end

	-- Seed the Random Generator
	if(self.Seed > 0) then
		math.randomseed(self.Seed);
	else
		-- Fast cross-platform seed generation without external process spawning.
		local seed = os.time() + math.floor(os.clock() * 1000000);
		if _VERSION == "Lua 5.1" and not rawget(_G, "jit") then
			seed = seed % 2147483647;
		end
		math.randomseed(seed);
	end

	-- Initialize validator pool (lazy initialization for Overhaul #4)
	if self.enableValidatorPooling and not self.validatorPool then
		self.validatorPool = Allocator:newPool(function()
			return Validator:new();
		end, 5);
	end

	-- Check cache for parsed AST (Overhaul #4)
	local ast;
	if self.enableCaching then
		self.profiler:startSection("cache_lookup");
		ast = self.cache:getAST(code);
		self.profiler:endSection("cache_lookup");
		if ast then
			logger:info("AST cache hit - skipping parsing");
			return self:_applyStepsAndGenerate(ast, code, filename, startTime);
		end
	end

	logger:info("Parsing ...");
	if self.enableProfiling then
		self.profiler:startSection("parsing");
	end

	local sourceLen = string.len(code);
	ast = self.parser:parse(code);

	if self.enableProfiling then
		self.profiler:endSection("parsing");
	end

	-- Cache parsed AST (Overhaul #4)
	if self.enableCaching then
		self.cache:cacheAST(code, ast, filename);
	end

	-- Validate AST after parsing
	local validator = self.enableValidatorPooling and Allocator:acquire(self.validatorPool) or Validator:new();
	local errors, warnings = validator:validate(ast);
	if self.enableValidatorPooling then
		Allocator:release(self.validatorPool, validator);
	end

	if #errors > 0 then
		for _, err in ipairs(errors) do
			logger:warn(string.format("AST Validation Error: %s (%s)", err.message, err.context));
		end
	end
	if #warnings > 0 then
		for _, warn in ipairs(warnings) do
			logger:debug(string.format("AST Validation Warning: %s (%s)", warn.message, warn.context));
		end
	end

	return self:_applyStepsAndGenerate(ast, code, filename, startTime);
end

-- Helper method to apply steps and generate code (extracted for reuse in caching)
function Pipeline:_applyStepsAndGenerate(ast, code, filename, startTime)
	-- User Defined Steps
	for i, step in ipairs(self.steps) do
		local stepStartTime = gettime();
		logger:info(string.format("Applying Step \"%s\" ...", step.Name or "Unnamed"));
		
		if self.enableProfiling then
			self.profiler:startSection("step_" .. (step.Name or "unnamed"));
		end

		local newAst = step:apply(ast, self);
		if type(newAst) == "table" then
			ast = newAst;
		end
		
		if self.enableProfiling then
			self.profiler:endSection("step_" .. (step.Name or "unnamed"));
		end

		-- Validate AST after each step (using validator pool for Overhaul #4)
		local stepValidator = self.enableValidatorPooling and Allocator:acquire(self.validatorPool) or Validator:new();
		local stepErrors, stepWarnings = stepValidator:validate(ast);
		if self.enableValidatorPooling then
			Allocator:release(self.validatorPool, stepValidator);
		end

		if #stepErrors > 0 then
			for _, err in ipairs(stepErrors) do
				logger:warn(string.format("Post-%s Validation Error: %s (%s)", step.Name or "Unnamed", err.message, err.context));
			end
		end
		
		logger:info(string.format("Step \"%s\" Done in %.2f seconds", step.Name or "Unnamed", gettime() - stepStartTime));
	end

	-- Rename Variables Step
	if self.enableProfiling then
		self.profiler:startSection("rename_variables");
	end

	self:renameVariables(ast);

	if self.enableProfiling then
		self.profiler:endSection("rename_variables");
	end

	-- Generate code
	if self.enableProfiling then
		self.profiler:startSection("code_generation");
	end

	local generatedCode = self:unparse(ast);

	if self.enableProfiling then
		self.profiler:endSection("code_generation");
		self.profiler:endSection("total");
	end

	local timeDiff = gettime() - (startTime or gettime());
	logger:info(string.format("Obfuscation Done in %.2f seconds", timeDiff));

	logger:info(string.format("Generated Code size is %.2f%% of the Source Code size", (string.len(generatedCode) / string.len(code))*100))

	return generatedCode;
end

function Pipeline:unparse(ast)
	local startTime = gettime();
	logger:info("Generating Code ...");

	local unparsed = self.unparser:unparse(ast);

	local timeDiff = gettime() - startTime;
	logger:info(string.format("Code Generation Done in %.2f seconds", timeDiff));

	return unparsed;
end

function Pipeline:renameVariables(ast)
	local startTime = gettime();
	logger:info("Renaming Variables ...");


	local generatorFunction = self.namegenerator or Pipeline.NameGenerators.mangled;
	if(type(generatorFunction) == "table") then
		if (type(generatorFunction.prepare) == "function") then
			generatorFunction.prepare(ast);
		end
		generatorFunction = generatorFunction.generateName;
	end

	if not self.unparser:isValidIdentifier(self.VarNamePrefix) and #self.VarNamePrefix ~= 0 then
		logger:error(string.format("The Prefix \"%s\" is not a valid Identifier in %s", self.VarNamePrefix, self.LuaVersion));
	end

	local globalScope = ast.globalScope;
	globalScope:renameVariables({
		Keywords = self.conventions.Keywords;
		generateName = generatorFunction;
		prefix = self.VarNamePrefix;
	});

	local timeDiff = gettime() - startTime;
	logger:info(string.format("Renaming Done in %.2f seconds", timeDiff));
end

-- Get cache statistics (Overhaul #4)
function Pipeline:getCacheStats()
	return self.cache:getStats();
end

-- Get profiling report (Overhaul #4)
function Pipeline:getProfilingReport()
	return self.profiler:getAllStats();
end

-- Print performance report (Overhaul #4)
function Pipeline:printPerformanceReport()
	logger:info("=== Performance Report (Overhaul #4) ===");
	
	-- Cache statistics
	local cacheStats = self:getCacheStats();
	logger:info(string.format("Cache Stats: Hits=%d, Misses=%d, Hit Rate=%.1f%%", 
		cacheStats.hits, cacheStats.misses, cacheStats.hitRate));
	logger:info(string.format("  AST Cache Size: %d, Compilation Cache Size: %d, Evictions: %d",
		cacheStats.astCacheSize, cacheStats.compilationCacheSize, cacheStats.evictions));
	
	-- Profiling report
	logger:info("Profiling Report:");
	self.profiler:printReport();
	
	-- Validator pool statistics
	if self.validatorPool then
		local poolStats = Allocator:getPoolStats(self.validatorPool);
		logger:info(string.format("Validator Pool: Available=%d, InUse=%d, Created=%d, Reuse Rate=%.1f%%",
			poolStats.available, poolStats.inUse, poolStats.created, poolStats.reuseRate));
	end
	
	-- Memory statistics
	local memReport = Allocator:getMemoryReport();
	logger:info(string.format("Memory Pools - Tables: Available=%d, InUse=%d; StringBuilders: Available=%d, InUse=%d",
		memReport.tablePool.available, memReport.tablePool.inUse,
		memReport.stringBuilderPool.available, memReport.stringBuilderPool.inUse));
end

-- Clear caches and reset profiling (useful for batch operations)
function Pipeline:resetPerformanceData()
	self.cache:clear();
	self.profiler = Profiler:new();
	if self.validatorPool then
		Allocator:resetPool(self.validatorPool);
	end
	logger:info("Performance data cleared");
end

return Pipeline;
