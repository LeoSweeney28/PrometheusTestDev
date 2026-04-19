-- Performance Benchmark Test Suite
-- Tests for Overhaul #4 Performance Optimizations

-- Configure package.path for requiring Prometheus
local function script_path()
	local str = debug.getinfo(1, "S").source:sub(2)
	return str:match("(.*[/%\\])") or "";
end
local testPath = script_path();
local srcPath = testPath:gsub("[/\\]tests[/\\]*$", "/src/");
package.path = srcPath .. "?.lua;" .. package.path;

local prometheus = require("prometheus");
local Pipeline = prometheus.Pipeline;
local Cache = prometheus.Cache;
local Profiler = prometheus.Profiler;
local Allocator = prometheus.Allocator;
local Lazy = prometheus.Lazy;
local StreamingGenerator = prometheus.StreamingGenerator;

local logger = prometheus.Logger;
logger:setLevel("info");

-- Test Suite
local tests = {};

-- Test 1: Cache Functionality
function tests.testCaching()
    logger:info("=== Test 1: Cache Functionality ===");
    
    local cache = Cache:new(100);
    local code1 = "local x = 1; print(x);";
    local code2 = "local y = 2; print(y);";
    
    -- Create dummy ASTs
    local ast1 = { type = "Block"; statements = {} };
    local ast2 = { type = "Block"; statements = {} };
    
    -- Cache first code
    cache:cacheAST(code1, ast1, "test1.lua");
    
    -- Retrieve from cache (should hit)
    local retrieved = cache:getAST(code1);
    assert(retrieved == ast1, "Cache miss on first retrieval");
    
    -- Different code should miss
    local notFound = cache:getAST(code2);
    assert(notFound == nil, "Cache returned wrong result");
    
    -- Cache second code
    cache:cacheAST(code2, ast2, "test2.lua");
    local retrieved2 = cache:getAST(code2);
    assert(retrieved2 == ast2, "Cache miss on second code");
    
    -- Check stats
    local stats = cache:getStats();
    assert(stats.hits == 2, "Incorrect hit count");
    assert(stats.misses == 1, "Incorrect miss count");
    assert(stats.hitRate > 60 and stats.hitRate < 100, "Incorrect hit rate calculation");
    
    logger:info("✓ Cache functionality verified");
    logger:info(string.format("  Cache hit rate: %.1f%% (%d hits, %d misses)", 
        stats.hitRate, stats.hits, stats.misses));
end

-- Test 2: Lazy Evaluation
function tests.testLazyEvaluation()
    logger:info("=== Test 2: Lazy Evaluation ===");
    
    local computed = false;
    local lazyVal = Lazy.value(function()
        computed = true;
        return "lazy_result";
    end);
    
    assert(not computed, "Value computed too early");
    assert(not lazyVal:isComputed(), "Lazy value reports as computed");
    
    local result = lazyVal:getValue();
    assert(computed, "Lazy value not computed on access");
    assert(result == "lazy_result", "Wrong lazy value returned");
    assert(lazyVal:isComputed(), "Lazy value doesn't report as computed");
    
    logger:info("✓ Lazy evaluation verified");
end

-- Test 3: Lazy Memoization
function tests.testMemoization()
    logger:info("=== Test 3: Memoization ===");
    
    local callCount = 0;
    local expensive = function(x)
        callCount = callCount + 1;
        return x * 2;
    end
    
    local memoized = Lazy.memoize(expensive, 10);
    
    assert(memoized(5) == 10, "Wrong memoized result");
    assert(callCount == 1, "Function called wrong number of times");
    
    assert(memoized(5) == 10, "Wrong memoized result on second call");
    assert(callCount == 1, "Memoized function called again");
    
    assert(memoized(6) == 12, "Wrong result for different argument");
    assert(callCount == 2, "Memoization doesn't distinguish arguments");
    
    logger:info("✓ Memoization verified");
end

-- Test 4: Object Pooling
function tests.testObjectPooling()
    logger:info("=== Test 4: Object Pooling ===");
    
    local pool = Allocator:newPool(function()
        return { data = {} };
    end, 5);
    
    -- Acquire objects
    local obj1 = Allocator:acquire(pool);
    local obj2 = Allocator:acquire(pool);
    
    local stats = Allocator:getPoolStats(pool);
    assert(stats.inUse == 2, "Wrong in-use count");
    assert(stats.available == 3, "Wrong available count");
    
    -- Release objects
    Allocator:release(pool, obj1);
    Allocator:release(pool, obj2);
    
    stats = Allocator:getPoolStats(pool);
    assert(stats.inUse == 0, "Objects not released");
    assert(stats.available == 5, "Objects not returned to pool");
    
    logger:info("✓ Object pooling verified");
    logger:info(string.format("  Pool stats: Available=%d, InUse=%d, Created=%d, Reused=%d",
        stats.available, stats.inUse, stats.created, stats.reused));
end

-- Test 5: Table Pooling
function tests.testTablePooling()
    logger:info("=== Test 5: Table Pooling ===");
    
    local tbl1 = Allocator.acquireTable();
    tbl1.key1 = "value1";
    tbl1.key2 = "value2";
    
    local tbl2 = Allocator.acquireTable();
    tbl2.other = "data";
    
    Allocator.releaseTable(tbl1);
    Allocator.releaseTable(tbl2);
    
    -- Acquire should get pool objects (table should be cleared)
    local tbl3 = Allocator.acquireTable();
    assert(tbl3.key1 == nil, "Pool object not cleared");
    
    logger:info("✓ Table pooling verified");
end

-- Test 6: String Builder
function tests.testStringBuilder()
    logger:info("=== Test 6: String Builder ===");
    
    local sb = Allocator:newStringBuilder();
    sb:append("local "):append("x"):append(" = "):append("1");
    
    local result = sb:toString();
    assert(result == "local x = 1", "String builder produced wrong result");
    
    sb:clear();
    assert(sb:toString() == "", "String builder not cleared");
    
    logger:info("✓ String builder verified");
end

-- Test 7: Profiler Functionality
function tests.testProfiler()
    logger:info("=== Test 7: Profiler ===");
    
    local profiler = Profiler:new();
    
    -- Simulate work
    profiler:startSection("section1");
    for i = 1, 100 do
        math.sqrt(i);
    end
    profiler:endSection("section1");
    
    profiler:startSection("section2");
    for i = 1, 50 do
        math.sqrt(i);
    end
    profiler:endSection("section2");
    
    -- Get stats
    local stats1 = profiler:getStats("section1");
    local stats2 = profiler:getStats("section2");
    
    assert(stats1.calls == 1, "Wrong call count");
    assert(stats2.calls == 1, "Wrong call count");
    assert(stats1.totalTime > 0, "No time measured for section1");
    
    logger:info("✓ Profiler functionality verified");
    logger:info(string.format("  section1: %.4fms, section2: %.4fms", 
        stats1.totalTime, stats2.totalTime));
end

-- Test 8: Streaming Generator
function tests.testStreamingGenerator()
    logger:info("=== Test 8: Streaming Generator ===");
    
    local chunks = {};
    local generator = StreamingGenerator:new(function(chunk)
        table.insert(chunks, chunk);
    end);
    
    generator:write("local x = "):write("1"):writeLine(";");
    generator:write("print(x)");
    generator:finalize();
    
    local output = table.concat(chunks);
    assert(output:find("local x = 1"), "Missing code in output");
    assert(output:find("print"), "Missing print statement");
    
    logger:info("✓ Streaming generator verified");
    logger:info(string.format("  Generated %d bytes", #output));
end

-- Test 9: Pipeline with Caching
function tests.testPipelineWithCaching()
    logger:info("=== Test 9: Pipeline with Caching ===");
    
    -- Create a simple config
    local config = {
        LuaVersion = "Lua 5.1";
        PrettyPrint = false;
        Seed = 12345;
        Steps = {};  -- No steps for fast testing
    };
    
    local pipeline = Pipeline:fromConfig(config);
    
    -- First run (cache miss)
    local code = "local x = 1; print(x);";
    local result1 = pipeline:apply(code, "test.lua");
    
    local stats1 = pipeline:getCacheStats();
    assert(stats1.misses == 1, "Should have cache miss");
    
    -- Second run (cache hit)
    local result2 = pipeline:apply(code, "test.lua");
    
    local stats2 = pipeline:getCacheStats();
    assert(stats2.hits == 1, "Should have cache hit");
    assert(result1 == result2, "Results should be identical");
    
    logger:info("✓ Pipeline caching verified");
    logger:info(string.format("  Cache performance: %d hits, %d misses (%.1f%% hit rate)",
        stats2.hits, stats2.misses, stats2.hitRate));
end

-- Test 10: Profiling Integration
function tests.testProfilingIntegration()
    logger:info("=== Test 10: Profiling Integration ===");
    
    local config = {
        LuaVersion = "Lua 5.1";
        PrettyPrint = false;
        EnableProfiling = true;
        Steps = {};
    };
    
    local pipeline = Pipeline:fromConfig(config);
    local code = "local x = 1; local y = 2; return x + y;";
    
    local result = pipeline:apply(code, "profile_test.lua");
    
    local report = pipeline:getProfilingReport();
    assert(#report > 0, "No profiling data");
    
    -- Should have at least: parsing, code_generation, total
    local hasKey = false;
    for _, stat in ipairs(report) do
        if stat.name == "parsing" then
            hasKey = true;
            assert(stat.calls > 0, "Parsing should be called");
        end
    end
    assert(hasKey, "Parsing stat not found");
    
    logger:info("✓ Profiling integration verified");
    logger:info(string.format("  Captured %d profiling sections", #report));
end

-- Run all tests
function runAllTests()
    logger:info("Starting Performance Tests...\n");
    
    local passed = 0;
    local failed = 0;
    
    for name, test in pairs(tests) do
        local success, err = pcall(test);
        if success then
            passed = passed + 1;
        else
            failed = failed + 1;
            logger:error(string.format("✗ %s: %s", name, tostring(err)));
        end
    end
    
    logger:info("\n" .. string.rep("=", 50));
    logger:info(string.format("Test Results: %d passed, %d failed", passed, failed));
    logger:info(string.rep("=", 50));
    
    return failed == 0;
end

-- Run tests if executed directly
if debug.getinfo(2) == nil then
    local allPassed = runAllTests();
    os.exit(allPassed and 0 or 1);
end

return tests;
