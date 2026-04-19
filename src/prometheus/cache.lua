-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- cache.lua
--
-- This Script provides caching mechanisms for AST and compilation results to avoid redundant processing.

local logger = require("logger");

local Cache = {};

-- Set up metatable
Cache.__index = Cache;

-- Initialize cache storage
function Cache:new(maxSize)
	local cache = {
		astCache = {};
		astCacheOrder = {};
		compilationCache = {};
		compilationCacheOrder = {};
		maxSize = maxSize or 1000;
		hits = 0;
		misses = 0;
		evictions = 0;
	};
	setmetatable(cache, Cache);
	return cache;
end

local function removeFromOrder(order, key)
	for i, existing in ipairs(order) do
		if existing == key then
			table.remove(order, i);
			return;
		end
	end
end

local function touchKey(order, key)
	removeFromOrder(order, key);
	order[#order + 1] = key;
end

-- Generate cache key from code hash
local function hashCode(code)
	local hash = 5381;
	for i = 1, math.min(#code, 1000), 1 do
		hash = (hash * 33) + string.byte(code, i);
		hash = hash % 2147483647;
	end
	return tostring(hash);
end

-- Cache an AST with its source code
function Cache:cacheAST(code, ast, filename)
	filename = filename or "anonymous";
	local key = hashCode(code);

	if not self.astCache[key] and #self.astCacheOrder >= self.maxSize then
		local evictKey = table.remove(self.astCacheOrder, 1);
		if evictKey then
			self.astCache[evictKey] = nil;
			self.evictions = self.evictions + 1;
		end
	end

	self.astCache[key] = {
		key = key;
		code = code;
		ast = ast;
		filename = filename;
		timestamp = os.time();
	};
	touchKey(self.astCacheOrder, key);
end

-- Retrieve cached AST
function Cache:getAST(code)
	local key = hashCode(code);
	local entry = self.astCache[key];
	if entry then
		self.hits = self.hits + 1;
		touchKey(self.astCacheOrder, key);
		logger:debug(string.format("AST cache hit (total hits: %d)", self.hits));
		return entry.ast, entry.filename;
	end
	self.misses = self.misses + 1;
	return nil;
end

-- Cache compilation result
function Cache:cacheCompilation(stepName, astHash, config, result)
	local key = string.format("%s_%s_%s", stepName, astHash, tostring(config));

	if not self.compilationCache[key] and #self.compilationCacheOrder >= self.maxSize then
		local evictKey = table.remove(self.compilationCacheOrder, 1);
		if evictKey then
			self.compilationCache[evictKey] = nil;
			self.evictions = self.evictions + 1;
		end
	end

	self.compilationCache[key] = {
		key = key;
		result = result;
		timestamp = os.time();
	};
	touchKey(self.compilationCacheOrder, key);
end

-- Retrieve cached compilation result
function Cache:getCompilation(stepName, astHash, config)
	local key = string.format("%s_%s_%s", stepName, astHash, tostring(config));
	local entry = self.compilationCache[key];
	if entry then
		self.hits = self.hits + 1;
		touchKey(self.compilationCacheOrder, key);
		return entry.result;
	end
	self.misses = self.misses + 1;
	return nil;
end

-- Clear all caches
function Cache:clear()
	self.astCache = {};
	self.astCacheOrder = {};
	self.compilationCache = {};
	self.compilationCacheOrder = {};
	logger:debug("Cache cleared");
end

-- Get cache statistics
function Cache:getStats()
	local totalAttempts = self.hits + self.misses;
	local hitRate = totalAttempts > 0 and (self.hits / totalAttempts * 100) or 0;
	return {
		hits = self.hits;
		misses = self.misses;
		hitRate = hitRate;
		astCacheSize = #self.astCacheOrder;
		compilationCacheSize = #self.compilationCacheOrder;
		evictions = self.evictions;
	};
end

return Cache;
