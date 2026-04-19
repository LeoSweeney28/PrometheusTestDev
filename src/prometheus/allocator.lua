-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- allocator.lua
--
-- This Script provides memory pooling and efficient allocation strategies for hot paths in compilation.

local logger = require("logger");

local Allocator = {};

-- Object pool for frequently-allocated objects (e.g., scopes, blocks)
function Allocator:newPool(factory, initialSize)
	initialSize = initialSize or 100;
	
	local pool = {
		available = {};
		inUse = {};
		factory = factory;
		created = 0;
		reused = 0;
		returned = 0;
	};
	
	-- Pre-allocate initial objects
	for i = 1, initialSize do
		table.insert(pool.available, factory());
		pool.created = pool.created + 1;
	end
	
	logger:debug(string.format("Created object pool with %d initial objects", initialSize));
	
	return pool;
end

-- Acquire an object from pool (or create new if empty)
function Allocator:acquire(pool)
	local obj;
	if #pool.available > 0 then
		obj = table.remove(pool.available);
		pool.reused = pool.reused + 1;
	else
		obj = pool.factory();
		pool.created = pool.created + 1;
	end
	table.insert(pool.inUse, obj);
	return obj;
end

-- Return an object to pool (reset it first)
function Allocator:release(pool, obj)
	if obj.reset and type(obj.reset) == "function" then
		obj:reset();
	end
	
	for i, inUseObj in ipairs(pool.inUse) do
		if inUseObj == obj then
			table.remove(pool.inUse, i);
			break;
		end
	end
	
	table.insert(pool.available, obj);
	pool.returned = pool.returned + 1;
end

-- Reset pool (clear all in-use objects)
function Allocator:resetPool(pool)
	for _, obj in ipairs(pool.inUse) do
		if obj.reset and type(obj.reset) == "function" then
			obj:reset();
		end
		table.insert(pool.available, obj);
	end
	pool.inUse = {};
	logger:debug(string.format("Pool reset: returned %d objects to available", pool.returned));
end

-- Get pool statistics
function Allocator:getPoolStats(pool)
	return {
		available = #pool.available;
		inUse = #pool.inUse;
		created = pool.created;
		reused = pool.reused;
		returned = pool.returned;
		reuseRate = pool.created > 0 and (pool.reused / (pool.reused + pool.created) * 100) or 0;
	};
end

-- Table pool - for temporary table allocations in hot loops
local tablePool = Allocator:newPool(function() return {}; end, 500);

-- Acquire temporary table
function Allocator.acquireTable()
	return Allocator:acquire(tablePool);
end

-- Release temporary table
function Allocator.releaseTable(tbl)
	-- Clear table contents
	for k in pairs(tbl) do
		tbl[k] = nil;
	end
	Allocator:release(tablePool, tbl);
end

-- String builder for efficient string concatenation (avoid repeated concat in loops)
function Allocator:newStringBuilder(initialCapacity)
	initialCapacity = initialCapacity or 1024;
	
	return {
		buffer = {};
		size = 0;
		capacity = initialCapacity;
		
		append = function(self, str)
			if type(str) == "string" then
				table.insert(self.buffer, str);
				self.size = self.size + #str;
			end
			return self;
		end,
		
		toString = function(self)
			return table.concat(self.buffer);
		end,
		
		clear = function(self)
			self.buffer = {};
			self.size = 0;
		end,
		
		reset = function(self)
			self:clear();
		end,
		
		length = function(self)
			return self.size;
		end,
	};
end

-- String builder pool for hot paths (e.g., code generation loops)
local stringBuilderPool = Allocator:newPool(function() 
	return Allocator:newStringBuilder();
end, 100);

-- Acquire string builder
function Allocator.acquireStringBuilder()
	local sb = Allocator:acquire(stringBuilderPool);
	sb:clear();
	return sb;
end

-- Release string builder
function Allocator.releaseStringBuilder(sb)
	sb:clear();
	Allocator:release(stringBuilderPool, sb);
end

-- Memory report for diagnostics
function Allocator:getMemoryReport()
	return {
		tablePool = Allocator:getPoolStats(tablePool);
		stringBuilderPool = Allocator:getPoolStats(stringBuilderPool);
	};
end

return Allocator;
