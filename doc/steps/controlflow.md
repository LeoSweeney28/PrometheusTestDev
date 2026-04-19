---
description: Adds extra control-flow wrappers around statements
---

# ControlFlow

### Settings

| Name | type | description | Values |
| --- | --- | --- | --- |
| Threshold | number | Relative amount of eligible statements that are wrapped | 0 <= x <= 1 |
| MaxWrappers | number | Maximum number of nested wrappers for each selected statement | 1 <= x <= 3 |
| IncludeFalseBranchNoise | boolean | Adds a benign false branch with noise blocks | true, false |
| WrapInDoBlock | boolean | Wraps each generated if-block in an outer do-block | true, false |
| WrapControlStatements | boolean | Allows wrapping return/loop/branch statements as well | true, false |

### Example

```lua
print("Hello")
a = a + 1
```

Possible output shape:

```lua
do
    if (4 + 1) > 4 then
        print("Hello")
    else
        do
        end
    end
end

do
    if (8 - 1) == 7 then
        a = a + 1
    end
end
```
