-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- SafeEnv.lua
--
-- This Script provides a type-safe runtime environment wrapper for generated code.
-- It adds runtime type guards to prevent boolean-arithmetic and similar type mismatches.

local SafeEnv = {};

local function safeArithmetic(op, a, b)
	if type(a) ~= "number" then
		error("attempt to perform arithmetic on a " .. type(a) .. " value", 2);
	end
	if type(b) ~= "number" then
		error("attempt to perform arithmetic on a " .. type(b) .. " value", 2);
	end

	if op == "add" then
		return a + b;
	elseif op == "sub" then
		return a - b;
	elseif op == "mul" then
		return a * b;
	elseif op == "div" then
		if b == 0 then
			error("attempt to divide by zero", 2);
		end
		return a / b;
	elseif op == "mod" then
		if b == 0 then
			error("attempt to perform modulo by zero", 2);
		end
		return a % b;
	elseif op == "pow" then
		return a ^ b;
	end
	error("unknown arithmetic operation", 2);
end

local function safeUnaryMinus(a)
	if type(a) ~= "number" then
		error("attempt to negate a " .. type(a) .. " value", 2);
	end
	return -a;
end

local function safeLen(a)
	if type(a) ~= "string" and type(a) ~= "table" then
		error("attempt to get length of a " .. type(a) .. " value", 2);
	end
	return #a;
end

local function safeConcat(...)
	local args = {...};
	local result = "";
	for i, v in ipairs(args) do
		if type(v) ~= "string" and type(v) ~= "number" then
			error("attempt to concatenate a " .. type(v) .. " value", 2);
		end
		result = result .. tostring(v);
	end
	return result;
end

local function safeIndex(table_, index)
	if type(table_) ~= "table" then
		local mt = getmetatable(table_);
		if mt and mt.__index then
			return mt.__index(table_, index);
		end
		error("attempt to index a " .. type(table_) .. " value", 2);
	end
	return table_[index];
end

local function safeNewIndex(table_, index, value)
	if type(table_) ~= "table" then
		local mt = getmetatable(table_);
		if mt and mt.__newindex then
			return mt.__newindex(table_, index, value);
		end
		error("attempt to index a " .. type(table_) .. " value", 2);
	end
	table_[index] = value;
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		local mt = getmetatable(fn);
		if mt and mt.__call then
			return mt.__call(fn, ...);
		end
		error("attempt to call a " .. type(fn) .. " value", 2);
	end
	return fn(...);
end

function SafeEnv:create(baseEnv)
	baseEnv = baseEnv or _G;
	
	local safeEnv = {
		-- Safe arithmetic operators
		__add = function(a, b) return safeArithmetic("add", a, b); end;
		__sub = function(a, b) return safeArithmetic("sub", a, b); end;
		__mul = function(a, b) return safeArithmetic("mul", a, b); end;
		__div = function(a, b) return safeArithmetic("div", a, b); end;
		__mod = function(a, b) return safeArithmetic("mod", a, b); end;
		__pow = function(a, b) return safeArithmetic("pow", a, b); end;
		__unm = function(a) return safeUnaryMinus(a); end;
		__len = function(a) return safeLen(a); end;
		__concat = function(...) return safeConcat(...); end;
		__index_safe = function(table_, index) return safeIndex(table_, index); end;
		__newindex_safe = function(table_, index, value) return safeNewIndex(table_, index, value); end;
		__call_safe = function(fn, ...) return safeCall(fn, ...); end;

		-- Standard library access
		print = baseEnv.print;
		tostring = baseEnv.tostring;
		tonumber = baseEnv.tonumber;
		type = baseEnv.type;
		pairs = baseEnv.pairs;
		ipairs = baseEnv.ipairs;
		next = baseEnv.next;
		select = baseEnv.select;
		unpack = baseEnv.unpack or table.unpack;
		math = baseEnv.math;
		string = baseEnv.string;
		table = baseEnv.table;
		getmetatable = baseEnv.getmetatable;
		setmetatable = baseEnv.setmetatable;
		rawget = baseEnv.rawget;
		rawset = baseEnv.rawset;
		rawlen = baseEnv.rawlen;
		error = baseEnv.error;
		assert = baseEnv.assert;
		pcall = baseEnv.pcall;
		xpcall = baseEnv.xpcall;
		load = baseEnv.load;
		loadstring = baseEnv.loadstring;
		debug = baseEnv.debug;
		os = baseEnv.os;
		io = baseEnv.io;
	};

	-- Whitelist control
	safeEnv._G = safeEnv;
	safeEnv.coroutine = baseEnv.coroutine;

	return safeEnv;
end

return SafeEnv;
