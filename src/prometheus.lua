-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- prometheus.lua
--
-- This file is the entrypoint for Prometheus

-- Configure package.path for require
local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/%\\])")
end

local oldPkgPath = package.path;
package.path = script_path() .. "?.lua;" .. package.path;

-- Math.random Fix for Lua5.1
-- Check if fix is needed
if not pcall(function()
    return math.random(1, 2^40);
end) then
    if not _G.__prometheus_random_state then
        local seed = math.floor(os.time() + (os.clock() * 1000000));
        _G.__prometheus_random_state = seed % 2147483647;
        if _G.__prometheus_random_state <= 0 then
            _G.__prometheus_random_state = 1;
        end
    end

    local function nextRandomValue()
        _G.__prometheus_random_state = (_G.__prometheus_random_state * 1103515245 + 12345) % 2147483647;
        return _G.__prometheus_random_state;
    end

    rawset(math, "randomseed", function(seed)
        if seed == nil then
            seed = math.floor(os.time() + (os.clock() * 1000000));
        end
        _G.__prometheus_random_state = tonumber(seed) % 2147483647;
        if _G.__prometheus_random_state <= 0 then
            _G.__prometheus_random_state = 1;
        end
    end)

    rawset(math, "random", function(a, b)
        local value = nextRandomValue();
        if a == nil and b == nil then
            return value / 2147483647;
        end
        if b == nil then
            return (value % a) + 1;
        end
        if a > b then
            a, b = b, a;
        end
        return a + (value % (b - a + 1));
    end)
end

-- newproxy polyfill
_G.newproxy = _G.newproxy or function(arg)
    if arg then
        return setmetatable({}, {});
    end
    return {};
end


-- Require Prometheus Submodules
local Pipeline = require("prometheus.pipeline");
local highlight = require("highlightlua");
local colors = require("colors");
local Logger = require("logger");
local Presets = require("presets");
local Config = require("config");
local util = require("prometheus.util");
local SafeEnv = require("prometheus.SafeEnv");
local Validator = require("prometheus.validator");
local StepUtils = require("prometheus.StepUtils");
local AstBuilder = require("prometheus.AstBuilder");
local StepRegistry = require("prometheus.StepRegistry");
local Cache = require("prometheus.cache");
local Lazy = require("prometheus.lazy");
local Allocator = require("prometheus.allocator");
local StreamingGenerator = require("prometheus.streaming");
local Profiler = require("prometheus.profiler");
-- Advanced Obfuscation Techniques (Overhaul #5)
local Polymorphic = require("prometheus.polymorphic");
local Complexity = require("prometheus.complexity");

-- Initialize built-in steps in registry
StepRegistry:registerBuiltins();

-- Restore package.path
package.path = oldPkgPath;

-- Export
return {
    Pipeline = Pipeline;
    colors = colors;
    Config = util.readonly(Config); -- Readonly
    Logger = Logger;
    highlight = highlight;
    Presets = Presets;
    SafeEnv = SafeEnv;
    Validator = Validator;
    StepUtils = StepUtils;
    AstBuilder = AstBuilder;
    StepRegistry = StepRegistry;
    Cache = Cache;
    Lazy = Lazy;
    Allocator = Allocator;
    StreamingGenerator = StreamingGenerator;
    Profiler = Profiler;
    -- Advanced Obfuscation (Overhaul #5)
    Polymorphic = Polymorphic;
    Complexity = Complexity;
}

