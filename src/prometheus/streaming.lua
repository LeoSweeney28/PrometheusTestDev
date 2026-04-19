-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- streaming.lua
--
-- This Script provides streaming/incremental code generation to reduce memory pressure and enable progressive output.

local logger = require("logger");
local Allocator = require("prometheus.allocator");

local StreamingGenerator = {};

-- Create a streaming code generator
function StreamingGenerator:new(outputFn)
	outputFn = outputFn or function(chunk) return chunk; end;
	
	local generator = {
		outputFn = outputFn;
		buffer = Allocator.acquireStringBuilder();
		totalGenerated = 0;
		flushCount = 0;
		bufferThreshold = 8192; -- Flush when buffer exceeds 8KB
	};
	
	setmetatable(generator, self);
	self.__index = self;
	
	return generator;
end

-- Append code to buffer with automatic flushing
function StreamingGenerator:write(code)
	if type(code) == "string" and #code > 0 then
		self.buffer:append(code);
		
		-- Auto-flush if buffer grows too large
		if self.buffer:length() >= self.bufferThreshold then
			self:flush();
		end
	end
	return self;
end

-- Append with newline
function StreamingGenerator:writeLine(code)
	self:write(code or "");
	self:write("\n");
	return self;
end

-- Append formatted code
function StreamingGenerator:writeFormat(format, ...)
	self:write(string.format(format, ...));
	return self;
end

-- Flush buffer to output
function StreamingGenerator:flush()
	if self.buffer:length() > 0 then
		local chunk = self.buffer:toString();
		self.totalGenerated = self.totalGenerated + #chunk;
		self.flushCount = self.flushCount + 1;
		
		if self.flushCount % 10 == 0 then
			logger:debug(string.format("StreamingGenerator flushed %d times, total: %d bytes", 
				self.flushCount, self.totalGenerated));
		end
		
		self.outputFn(chunk);
		self.buffer:clear();
	end
	return self;
end

-- Finalize and get final output
function StreamingGenerator:finalize()
	self:flush();
	Allocator.releaseStringBuilder(self.buffer);
	logger:debug(string.format("StreamingGenerator finalized: %d total bytes, %d flushes", 
		self.totalGenerated, self.flushCount));
	return self.totalGenerated;
end

-- Batch streaming generator that buffers output to a table (for testing/testing)
function StreamingGenerator:newBatchGenerator()
	local chunks = {};
	
	return StreamingGenerator:new(function(chunk)
		table.insert(chunks, chunk);
	end), chunks;
end

-- Concurrent streaming generator (simulated via coroutines)
function StreamingGenerator:newConcurrentGenerator(concurrency)
	concurrency = concurrency or 2;
	local workers = {};
	local taskQueue = {};
	local results = {};
	
	for i = 1, concurrency do
		workers[i] = coroutine.create(function()
			while true do
				local task = table.remove(taskQueue, 1);
				if not task then
					coroutine.yield();
				else
					local result = task.fn();
					table.insert(results, { index = task.index, result = result });
				end
			end
		end);
	end
	
	return {
		addTask = function(fn, index)
			table.insert(taskQueue, { fn = fn, index = index });
		end,
		executeAll = function()
			-- Execute all pending tasks
			while #taskQueue > 0 do
				for i, worker in ipairs(workers) do
					if coroutine.status(worker) ~= "dead" then
						coroutine.resume(worker);
					end
				end
			end
			-- Sort results by original index
			table.sort(results, function(a, b) return a.index < b.index; end);
			return results;
		end,
	};
end

-- Streaming validator that checks code as it's generated
function StreamingGenerator:newValidatingGenerator()
	local validationResults = {};
	
	return StreamingGenerator:new(function(chunk)
		-- Could validate each chunk for basic syntax
		-- For now, just collect for analysis
		table.insert(validationResults, {
			chunk = chunk;
			size = #chunk;
			timestamp = os.time();
		});
	end), validationResults;
end

return StreamingGenerator;
