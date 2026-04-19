-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- lazy.lua
--
-- This Script provides lazy evaluation helpers for deferred processing of expensive transforms.

local logger = require("logger");

local Lazy = {};

-- Create a lazy-evaluated value
function Lazy.value(computeFn, args)
	args = args or {};
	local cache = { computed = false, value = nil, args = args };
	
	return {
		getValue = function()
			if not cache.computed then
				logger:debug("Computing lazy value...");
				cache.value = computeFn(unpack(cache.args));
				cache.computed = true;
			end
			return cache.value;
		end,
		isComputed = function()
			return cache.computed;
		end,
	};
end

-- Create a lazy-evaluated function that only runs if needed
function Lazy.step(stepFn, threshold)
	threshold = threshold or 0.5;
	local step = {};

	function step:shouldRun()
		return math.random() <= threshold;
	end

	function step:run(ast, pipeline)
		if step:shouldRun() then
			logger:debug("Executing lazy step...");
			return stepFn(ast, pipeline);
		end
		logger:debug("Skipping lazy step (threshold not met)");
		return ast;
	end

	return step;
end

-- Chain multiple lazy computations
function Lazy.chain(...)
	local computations = { ... };
	return {
		execute = function()
			local results = {};
			for i, computation in ipairs(computations) do
				if computation.getValue then
					table.insert(results, computation:getValue());
				elseif type(computation) == "function" then
					table.insert(results, computation());
				else
					table.insert(results, computation);
				end
			end
			return unpack(results);
		end,
	};
end

-- Batch lazy computations for parallel-style execution (coroutine-based)
function Lazy.batch(tasks)
	local coroutines = {};
	local results = {};
	
	for i, task in ipairs(tasks) do
		coroutines[i] = coroutine.create(function()
			logger:debug(string.format("Starting batch task %d/%d", i, #tasks));
			return task();
		end);
	end
	
	return {
		executeAll = function()
			for i, coro in ipairs(coroutines) do
				if coroutine.status(coro) == "suspended" then
					local success, result = coroutine.resume(coro);
					if success then
						table.insert(results, result);
					else
						logger:warn(string.format("Batch task %d failed: %s", i, tostring(result)));
					end
				end
			end
			return results;
		end,
		executeSequential = function()
			-- Fallback: execute all coroutines to completion sequentially
			for i, coro in ipairs(coroutines) do
				while coroutine.status(coro) == "suspended" do
					local success, result = coroutine.resume(coro);
					if not success then
						logger:warn(string.format("Batch task %d failed: %s", i, tostring(result)));
						break;
					end
					if coroutine.status(coro) == "dead" then
						if result then
							table.insert(results, result);
						end
						break;
					end
				end
			end
			return results;
		end,
	};
end

-- Memoize a function to cache results based on arguments
function Lazy.memoize(fn, maxSize)
	maxSize = maxSize or 100;
	local cache = {};
	local order = {};
	
	return function(...)
		local args = { ... };
		local key = table.concat(args, "_");
		
		if cache[key] then
			logger:debug(string.format("Memoize hit for key: %s", key));
			return cache[key];
		end
		
		-- Implement simple LRU eviction
		if #order >= maxSize then
			local oldKey = table.remove(order, 1);
			cache[oldKey] = nil;
			logger:debug(string.format("Memoize evicted key: %s", oldKey));
		end
		
		logger:debug(string.format("Memoize computing for key: %s", key));
		local result = fn(unpack(args));
		cache[key] = result;
		table.insert(order, key);
		
		return result;
	end;
end

return Lazy;
