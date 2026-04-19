-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- StepRegistry.lua
--
-- This Script provides a plugin-based step registry system for dynamic step loading and registration.
-- Enables users to create custom obfuscation steps.

local logger = require("logger");

local StepRegistry = {};
StepRegistry.steps = {};
StepRegistry.stepMetadata = {};

-- Register a step
function StepRegistry:register(name, stepClass, metadata)
	if self.steps[name] then
		logger:warn(string.format("Overwriting previously registered step: %s", name));
	end
	
	if not stepClass or type(stepClass.new) ~= "function" then
		logger:error(string.format("Invalid step class for %s: must have :new() method", name));
	end
	
	self.steps[name] = stepClass;
	self.stepMetadata[name] = metadata or {
		name = name;
		description = stepClass.Description or "No description";
		author = "unknown";
		version = "1.0";
	};
	
	logger:debug(string.format("Registered step: %s", name));
end

-- Get a registered step
function StepRegistry:get(name)
	return self.steps[name];
end

-- Check if a step is registered
function StepRegistry:exists(name)
	return self.steps[name] ~= nil;
end

-- List all registered steps
function StepRegistry:list()
	local stepList = {};
	for name, stepClass in pairs(self.steps) do
		table.insert(stepList, {
			name = name;
			description = self.stepMetadata[name] and self.stepMetadata[name].description or "No description";
		});
	end
	return stepList;
end

-- Get metadata for a step
function StepRegistry:getMetadata(name)
	return self.stepMetadata[name];
end

-- Create a step instance
function StepRegistry:create(name, settings)
	local stepClass = self:get(name);
	if not stepClass then
		logger:error(string.format("Step not found: %s", name));
	end
	return stepClass:new(settings or {});
end

-- Register all built-in steps
function StepRegistry:registerBuiltins()
	local steps = require("prometheus.steps");
	
	local builtins = {
		"WrapInFunction";
		"SplitStrings";
		"Vmify";
		"ConstantArray";
		"ProxifyLocals";
		"AntiTamper";
		"EncryptStrings";
		"NumbersToExpressions";
		"AddVararg";
		"WatermarkCheck";
		"OpaquePredicates";
		"BooleanExpressionInversion";
		"IndirectFunctionCalls";
		"FunctionParameterShuffle";
		"ControlFlow";
	};
	
	for _, stepName in ipairs(builtins) do
		local stepClass = steps[stepName];
		if stepClass then
			self:register(stepName, stepClass, {
				name = stepName;
				description = stepClass.Description or "No description";
				author = "Prometheus";
				builtIn = true;
			});
		end
	end
end

-- Unregister a step
function StepRegistry:unregister(name)
	if self.steps[name] then
		self.steps[name] = nil;
		self.stepMetadata[name] = nil;
		logger:debug(string.format("Unregistered step: %s", name));
		return true;
	end
	return false;
end

-- Get step dependencies (for future use)
function StepRegistry:getDependencies(name)
	local metadata = self:getMetadata(name);
	if metadata and metadata.dependencies then
		return metadata.dependencies;
	end
	return {};
end

-- Validate step pipeline (check for missing dependencies)
function StepRegistry:validatePipeline(stepNames)
	local errors = {};
	for _, stepName in ipairs(stepNames) do
		if not self:exists(stepName) then
			table.insert(errors, string.format("Step not found: %s", stepName));
		else
			local deps = self:getDependencies(stepName);
			for _, dep in ipairs(deps) do
				if not self:exists(dep) then
					table.insert(errors, string.format("Step %s depends on missing step: %s", stepName, dep));
				end
			end
		end
	end
	return errors;
end

return StepRegistry;
