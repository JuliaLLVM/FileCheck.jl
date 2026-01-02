# FileCheck.jl

A Julia wrapper around LLVM's [FileCheck](https://llvm.org/docs/CommandGuide/FileCheck.html) tool for pattern-based file verification. Useful for testing compiler output, IR transformations, and other text-based verification tasks.


## Quick Start

The package provides a `@filecheck` macro that lets you write check patterns inline with Julia code:

```julia
using Test, FileCheck

@test @filecheck begin
    @check "hello"
    "hello world"
end
```

The last expression in the block is the input to verify (stringified if necessary). Check directives specify patterns that must appear in the input.


## Check Directives

The available checking macros closely follow FileCheck's functionality:

| Macro | Description |
|-------|-------------|
| `@check` | Match a pattern anywhere in the remaining input |
| `@check_label` | Match a pattern and reset the match position (useful for sections) |
| `@check_next` | Match on the line immediately following the previous match |
| `@check_same` | Match on the same line as the previous match |
| `@check_not` | Verify a pattern does *not* appear before the next positive match |
| `@check_dag` | Match patterns in any order (unordered checks) |
| `@check_count n` | Match a pattern exactly `n` times |
| `@check_empty` | Match an empty line |
