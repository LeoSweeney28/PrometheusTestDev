-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- profiler.lua
--
-- This Script provides performance profiling and benchmarking for pipeline optimization.

local logger = require("logger");

local Profiler = {};

-- Get current time in milliseconds
local function getTimeMs()
	return os.clock() * 1000;
end

-- Create a new profiler
function Profiler:new()
	local profiler = {
		timings = {};
		samples = {};
		startTime = nil;
		enabled = true;
	};
	
	setmetatable(profiler, self);
	self.__index = self;
	
	return profiler;
end

-- Start profiling a section
function Profiler:startSection(name)
	if not self.enabled then return; end
	
	if not self.timings[name] then
		self.timings[name] = {
			name = name;
			calls = 0;
			totalTime = 0;
			minTime = math.huge;
			maxTime = 0;
			samples = {};
		};
	end
	
	self.timings[name].startTime = getTimeMs();
end

-- End profiling a section
function Profiler:endSection(name)
	if not self.enabled or not self.timings[name] or not self.timings[name].startTime then 
		return; 
	end
	
	local elapsed = getTimeMs() - self.timings[name].startTime;
	local timing = self.timings[name];
	
	timing.calls = timing.calls + 1;
	timing.totalTime = timing.totalTime + elapsed;
	timing.minTime = math.min(timing.minTime, elapsed);
	timing.maxTime = math.max(timing.maxTime, elapsed);
	
	-- Keep last 100 samples for trend analysis
	if #timing.samples >= 100 then
		table.remove(timing.samples, 1);
	end
	table.insert(timing.samples, elapsed);
	
	timing.startTime = nil;
end

-- Measure execution time of a function
function Profiler:measure(name, fn, ...)
	self:startSection(name);
	local results = { fn(...) };
	self:endSection(name);
	return unpack(results);
end

-- Get timing statistics for a section
function Profiler:getStats(name)
	local timing = self.timings[name];
	if not timing then
		return nil;
	end
	
	local avgTime = timing.calls > 0 and (timing.totalTime / timing.calls) or 0;
	
	-- Calculate standard deviation
	local variance = 0;
	for _, sample in ipairs(timing.samples) do
		variance = variance + (sample - avgTime) ^ 2;
	end
	variance = variance / math.max(1, #timing.samples);
	local stdDev = math.sqrt(variance);
	
	return {
		name = name;
		calls = timing.calls;
		totalTime = timing.totalTime;
		avgTime = avgTime;
		minTime = timing.minTime;
		maxTime = timing.maxTime;
		stdDev = stdDev;
		samples = #timing.samples;
	};
end

-- Get all statistics
function Profiler:getAllStats()
	local stats = {};
	for name, _ in pairs(self.timings) do
		table.insert(stats, self:getStats(name));
	end
	
	-- Sort by total time (descending)
	table.sort(stats, function(a, b) return a.totalTime > b.totalTime; end);
	
	return stats;
end

-- Print profiling report
function Profiler:printReport()
	local stats = self:getAllStats();
	local totalTime = 0;
	
	for _, stat in ipairs(stats) do
		totalTime = totalTime + stat.totalTime;
	end
	
	logger:info("=== Performance Profile ===");
	logger:info(string.format("%-30s %10s %10s %10s %10s %10s", 
		"Section", "Calls", "Total(ms)", "Avg(ms)", "Min(ms)", "Max(ms)"));
	logger:info(string.rep("-", 90));
	
	for _, stat in ipairs(stats) do
		local pct = totalTime > 0 and (stat.totalTime / totalTime * 100) or 0;
		logger:info(string.format("%-30s %10d %10.2f %10.2f %10.2f %10.2f (%.1f%%)", 
			stat.name, stat.calls, stat.totalTime, stat.avgTime, stat.minTime, stat.maxTime, pct));
	end
	
	logger:info(string.rep("-", 90));
	logger:info(string.format("%-30s %10s %10.2f", "TOTAL", "", totalTime));
end

-- Export profiling data as JSON-like table
function Profiler:exportData()
	return {
		timestamp = os.time();
		timings = self.timings;
		stats = self:getAllStats();
	};
end

-- Compare two profiling reports
function Profiler.compare(prof1, prof2)
	logger:info("=== Performance Comparison ===");
	
	local stats1 = prof1:getAllStats();
	local stats2 = prof2:getAllStats();
	
	logger:info(string.format("%-30s %12s %12s %12s", 
		"Section", "Before(ms)", "After(ms)", "Change(%)"));
	logger:info(string.rep("-", 70));
	
	for i, stat1 in ipairs(stats1) do
		local stat2 = stats2[i];
		if stat2 then
			local change = stat1.totalTime > 0 and 
				((stat2.totalTime - stat1.totalTime) / stat1.totalTime * 100) or 0;
			local indicator = change < 0 and "✓" or (change > 0 and "✗" or "=");
			logger:info(string.format("%-30s %12.2f %12.2f %12.2f%s", 
				stat1.name, stat1.totalTime, stat2.totalTime, change, indicator));
		end
	end
end

-- Global profiler instance
Profiler.global = Profiler:new();

return Profiler;
