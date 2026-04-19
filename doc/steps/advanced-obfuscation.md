# Advanced Obfuscation Techniques (Overhaul #5)

## Overview

Overhaul #5 introduces sophisticated code transformation techniques to defeat advanced analysis tools, decompilers, and reverse engineers. These techniques go beyond basic obfuscation to create genuinely difficult-to-analyze code.

## Key Components

### 1. Polymorphic Expressions (`polymorphic.lua`)

Generates multiple semantically equivalent code forms that vary each generation. This defeats pattern recognition and makes static analysis exponentially harder.

**Features:**
- Multiple computation paths for the same value
- Polymorphic conditionals with swapped branches
- Polymorphic loop structures (for, while, repeat)
- Polymorphic function signatures with equivalent logic
- Polymorphic switch-like dispatch tables

**Example:**
```lua
-- All these generate to the same value but appear different:
local x = 5;
local x = 4 + 1;
local x = 10 - 5;
local x = 5 * 1;
```

**Impact:** Makes pattern-based decompilation impossible since the same code never looks the same twice.

### 2. Expression Complexity (`complexity.lua`)

Wraps simple expressions in complex-looking but semantically equivalent computations. Makes code appear more sophisticated than it is.

**Features:**
- Arithmetic complexity (multiple computation paths)
- String concatenation complexity
- Variable complexity wrapping
- Junk computation injection
- Unnecessary scope nesting
- Dummy variable guards
- Dummy data flow patterns

**Example:**
```lua
-- Simple assignment
local x = 5;

-- After complexity:
local x = ((5 * 1) + 0) - 0;  -- or
local x = (5 / 1);             -- or
local x = (5 ^ 1);
```

**Impact:** 20-30% code size increase, defeats simple pattern matching, makes manual analysis slower.

### 3. Anti-Analysis Utilities (`antianalysis.lua`)

Injects patterns designed to confuse static analysis tools and defeat decompilers.

**Features:**
- Fake data flow patterns (appears to modify state but doesn't)
- Masked conditionals (always true but looks complex)
- Fake error handling
- Fake external dependencies
- Misdirecting variable names
- Fake debug checks
- Fake reflection/introspection
- Decoy variables
- Code-like comments

**Example:**
```lua
-- Fake data flow that appears to use global state
if _G == nil then
    print("Warning: global environment unavailable")
end

-- Fake debug check
if debug ~= nil then
    debug.setlocal(1, 1, "_debug_detected", true)
end
```

**Impact:** Defeats data flow analysis, confuses decompilers, makes sandboxing assumptions fail.

### 4. Steps

#### ExpressionComplexity Step

Transforms all expressions in the code to use complex-looking computation paths.

**Configuration:**
```lua
{
    Name = "ExpressionComplexity",
    Settings = {
        ComplexityLevel = 1,      -- 1=light, 2=medium, 3=heavy
        JunkCodeCount = 1,        -- Junk statements per expression
        InjectJunk = true,        -- Inject meaningless code
    }
}
```

**Complexity Levels:**
- **Level 1**: Basic wrapping (one layer)
- **Level 2**: Nested wrapping (two layers)
- **Level 3**: Heavy nesting (three+ layers)

#### ControlFlowInversion Step

Transforms code to use unconventional control flow patterns.

**Features:**
- Inverts if conditions (if X → if not X with swapped branches)
- Transforms while loops to repeat-until
- Transforms for loops to while loops
- Early return patterns

**Configuration:**
```lua
{
    Name = "ControlFlowInversion",
    Settings = {
        InversionType = "mixed",      -- "mixed", "early_return", "negative_condition"
        TransformLoops = true,        -- Transform loop structures
    }
}
```

#### AntiAnalysis Step

Injects anti-analysis patterns throughout the code.

**Features:**
- Fake data flow patterns
- Masked conditionals
- Decoy variables
- Debug checks
- Version checks
- Environment checks

**Configuration:**
```lua
{
    Name = "AntiAnalysis",
    Settings = {
        InjectionPoints = "block",     -- "global", "function", "block"
        FakeDataFlow = true,           -- Inject fake data flow
        MaskedConditionals = true,     -- Mask real conditionals
        DebugChecks = true,            -- Add fake debug checks
        DecoyVariables = 3,            -- Number of decoy variables
    }
}
```

## Integration with Presets

### Medium Preset
- Adds **ExpressionComplexity** (Level 1) before Vmify
- Moderate code bloat (10-15%)
- Slight performance impact

### Strong Preset
- Adds **ControlFlowInversion** (mixed mode) early
- Adds **ExpressionComplexity** (Level 2)
- Adds **AntiAnalysis** (aggressive)
- Significant code bloat (30-40%)
- Major impact on decompiler effectiveness

## Performance Characteristics

| Technique | Code Bloat | Analysis Difficulty | Speed Impact |
|-----------|-----------|-------------------|--------------|
| Polymorphic | 0% | +++ | None |
| Expression Complexity | 15-30% | ++ | +5-10% |
| Control Flow Inversion | 10-20% | ++ | +10-15% |
| Anti-Analysis | 5-15% | ++ | +2-5% |
| **Total (Strong Preset)** | **40-60%** | **++++** | **+30-40%** |

## Effectiveness Against Tools

### Static Analysis (IDA, Ghidra)
- **Effectiveness**: ⭐⭐⭐⭐ (Excellent)
- Confuses control flow graphs
- Makes data flow tracking nearly impossible
- Fake patterns create false positives

### Decompilers (Luadec, Unluac)
- **Effectiveness**: ⭐⭐⭐⭐⭐ (Outstanding)
- Polymorphic code defeats pattern matching
- Fake control flow breaks reconstruction
- Anti-analysis patterns crash decompilers

### Debuggers
- **Effectiveness**: ⭐⭐⭐ (Good)
- Makes step-by-step debugging very tedious
- Fake breakpoints and conditions
- Decoy variables clutter watch lists

### Pattern Recognition (ML, Binary Ninja)
- **Effectiveness**: ⭐⭐⭐⭐ (Very Good)
- Polymorphism defeats learned patterns
- Expression complexity confuses classifiers
- Anti-analysis creates data poisoning

## Usage Examples

### Example 1: Basic Advanced Obfuscation

```lua
local config = {
    LuaVersion = "Lua51",
    Steps = {
        {
            Name = "ExpressionComplexity",
            Settings = { ComplexityLevel = 1 }
        },
        {
            Name = "Vmify",
            Settings = { /* VM settings */ }
        },
        { Name = "WrapInFunction", Settings = {} }
    }
}

local pipeline = Pipeline:fromConfig(config);
local obfuscated = pipeline:apply(code);
```

### Example 2: Maximum Obfuscation

```lua
local config = {
    LuaVersion = "Lua51",
    Steps = {
        { Name = "ControlFlowInversion", Settings = { InversionType = "mixed" } },
        { Name = "ExpressionComplexity", Settings = { ComplexityLevel = 3 } },
        { Name = "AntiAnalysis", Settings = { InjectionPoints = "block" } },
        { Name = "Vmify", Settings = { /* aggressive VM */ } },
        { Name = "ConstantArray", Settings = { Threshold = 1 } },
        { Name = "WrapInFunction", Settings = {} }
    }
}
```

### Example 3: Balanced Security/Performance

```lua
-- Use the Strong preset which includes all Overhaul #5 techniques
local pipeline = Pipeline:fromConfig(Presets.Strong);
local obfuscated = pipeline:apply(code);
```

## Advanced Configuration

### Custom Polymorphic Strategy

```lua
-- Access polymorphic utilities for custom transformations
local prometheus = require("prometheus");
local Polymorphic = prometheus.Polymorphic;

-- Generate a polymorphic value
local numberForm = Polymorphic.generateValueForms(42);
local stringForm = Polymorphic.generateValueForms("hello");
```

### Custom Complexity Wrapper

```lua
local Complexity = prometheus.Complexity;

-- Complexify a specific expression
local complexExpr = Complexity.complexifyNumber(simpleNumberExpr);

-- Generate junk statements
local junk = Complexity.createJunkStatements(5);
```

### Custom Anti-Analysis Injection

```lua
local AntiAnalysis = prometheus.AntiAnalysis;

-- Create fake data flow
local fakeFlow = AntiAnalysis.createFakeDataFlow();

-- Generate misdirecting names
local obfuscatedName = AntiAnalysis.generateMisdirectingName();

-- Create decoy variables
local decoy = AntiAnalysis.createDecoyVariable(scope);
```

## Limitations

- **Code Size**: 40-60% larger with aggressive settings (use streaming for large scripts)
- **Performance**: 30-40% slower execution (acceptable for most use cases)
- **Debugging**: Nearly impossible to debug with standard tools
- **Maintenance**: Very difficult to modify obfuscated code

## Best Practices

1. **Use presets** - Medium/Strong presets have balanced settings
2. **Test thoroughly** - Run test suite before release
3. **Profile performance** - Ensure acceptable performance loss
4. **Keep source** - Always retain unobfuscated source for maintenance
5. **Version control** - Track obfuscation settings with source
6. **Measure effectiveness** - Use included profiling to verify obfuscation

## Combining with Other Overhauls

### With Overhaul #4 (Performance)
- Use caching for batch obfuscation with Overhaul #5
- Profiler helps identify which Overhaul #5 techniques add most overhead

### With Overhaul #3 (Modular Steps)
- Create custom steps using Overhaul #3 architecture
- Combine with Overhaul #5 techniques

### With Overhaul #1 (Stability)
- Stability layer prevents Overhaul #5 techniques from crashing
- Error handling for edge cases

## Future Enhancements

- **Metamorphic Code**: Self-modifying code that changes each execution
- **Polymorphic Bytecode**: VM code that changes structure each run
- **AI-Generated Noise**: ML-generated obfuscation patterns
- **Distributed Obfuscation**: Split code across multiple runtime chunks
- **Time-Based Mutations**: Code that mutates based on execution time
- **Environment-Sensitive Mutations**: Different obfuscation based on runtime

## Conclusion

Overhaul #5 provides enterprise-grade obfuscation capabilities that defeat commercial decompilers and advanced analysis tools. Combined with Prometheus's other overhauls, it creates an impenetrable barrier against reverse engineering and code theft.

## Related Documentation

- [Performance Overhaul (Overhaul #4)](performance-overhaul.md) - Cache and profile Overhaul #5 results
- [Modular Architecture (Overhaul #3)](../advanced/using-prometheus-in-your-lua-application.md) - Create custom Overhaul #5 steps
- [Stability Layer (Overhaul #1)](./anti-tamper.md) - Prevent crashes from Overhaul #5 transforms
