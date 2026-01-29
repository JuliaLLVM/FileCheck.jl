module FileCheck

import LLVM_jll

export @filecheck
export @check, @check_label, @check_next, @check_same,
       @check_not, @check_dag, @check_empty, @check_count

global filecheck_path::String
function __init__()
    global filecheck_path = joinpath(LLVM_jll.artifact_dir, "tools", "FileCheck")
end

function filecheck_exe(; adjust_PATH::Bool=true, adjust_LIBPATH::Bool=true)
    env = Base.invokelatest(
        LLVM_jll.JLLWrappers.adjust_ENV!,
        copy(ENV),
        LLVM_jll.PATH[],
        LLVM_jll.LIBPATH[],
        adjust_PATH,
        adjust_LIBPATH
    )

    return Cmd(Cmd([filecheck_path]); env)
end

function filecheck(f, input;
    match_full_lines::Bool=false,
    strict_whitespace::Bool=false,
    ignore_case::Bool=false,
    implicit_check_not::Union{Nothing,String,Vector{String}}=nothing,
    enable_var_scope::Bool=false,
    dump_input::Union{Nothing,String}=nothing,
    verbose::Bool=false,
    very_verbose::Bool=false,
    check_prefixes::Union{Nothing,Vector{String}}=nothing,
    defines::Union{Nothing,Dict{String,String}}=nothing,
    allow_empty::Bool=false,
)
    # FileCheck assumes that the input is available as a file
    mktemp() do path, input_io
        write(input_io, input)
        close(input_io)

        # call the function while capturing the output and result
        pipe = Pipe()
        pipe_initialized = Channel{Nothing}(1)
        reader = @async begin
            take!(pipe_initialized)
            read(pipe, String)
        end
        result = nothing
        io = IOContext(pipe)
        stats = redirect_stdio(; stdout=io, stderr=io) do
            put!(pipe_initialized, nothing)
            result = f(input)
        end
        if result !== nothing
          println(io)
          print(io, result)
        end
        close(pipe.in)
        output = fetch(reader)

        # now pass the collected output to FileCheck
        filecheck_io = Pipe()
        cmd = `$(filecheck_exe()) --color $path`
        match_full_lines && (cmd = `$cmd --match-full-lines`)
        strict_whitespace && (cmd = `$cmd --strict-whitespace`)
        ignore_case && (cmd = `$cmd --ignore-case`)
        verbose && (cmd = `$cmd -v`)
        very_verbose && (cmd = `$cmd -vv`)
        enable_var_scope && (cmd = `$cmd --enable-var-scope`)
        allow_empty && (cmd = `$cmd --allow-empty`)
        dump_input !== nothing && (cmd = `$cmd --dump-input=$dump_input`)
        if implicit_check_not !== nothing
            for pat in (implicit_check_not isa String ? [implicit_check_not] : implicit_check_not)
                cmd = `$cmd --implicit-check-not=$pat`
            end
        end
        if check_prefixes !== nothing
            cmd = `$cmd --check-prefixes=$(join(check_prefixes, ","))`
        end
        if defines !== nothing
            for (k, v) in defines
                cmd = `$cmd -D$k=$v`
            end
        end
        proc = run(pipeline(ignorestatus(cmd); stdin=IOBuffer(output), stdout=filecheck_io, stderr=filecheck_io); wait=false)
        close(filecheck_io.in)

        # collect the output of FileCheck
        reader = Threads.@spawn String(read(filecheck_io))
        Base.wait(proc)
        log = strip(fetch(reader))
        if !isempty(log)
            log = replace(log, path => "<checks>")
            log = replace(log, "<stdin>" => "<input>")
            log = replace(log, r"^Input file: .*\nCheck file: .*\n\n"m => "")
            log = replace(log, r"^-dump-input=help explains the following input dump\.\n?"m => "")
            println(stderr, log)
        end

        return success(proc)
    end
end

function parse_kwargs(args)
    kwargs = Dict{Symbol,Any}()
    for kwarg in args
        if kwarg isa Symbol
            kwargs[kwarg] = kwarg
        elseif Meta.isexpr(kwarg, :(=))
            kwargs[kwarg.args[1]] = kwarg.args[2]
        else
            throw(ArgumentError("Invalid keyword argument '$kwarg'"))
        end
    end
    return kwargs
end

# collect checks used in the @filecheck block by piggybacking on macro expansion
const checks = Tuple{Any,Bool,String,String}[]

macro check(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK", args[end]))
    nothing
end

macro check_label(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-LABEL", args[end]))
    nothing
end

macro check_next(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-NEXT", args[end]))
    nothing
end

macro check_same(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-SAME", args[end]))
    nothing
end

macro check_not(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-NOT", args[end]))
    nothing
end

macro check_dag(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-DAG", args[end]))
    nothing
end

macro check_empty(args...)
    kwargs = parse_kwargs(args[1:end-1])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-EMPTY", args[end]))
    nothing
end

macro check_count(args...)
    kwargs = parse_kwargs(args[1:end-2])
    cond = get(kwargs, :cond, nothing)
    literal = get(kwargs, :literal, false)
    push!(checks, (cond, literal, "CHECK-COUNT-$(args[end-1])", args[end]))
    nothing
end

"""
    @filecheck [kwargs...] ex

Run the expression `ex`, capture its stdout/stderr and return value, and verify the
combined output against LLVM FileCheck directives specified via nested `@check*` macros.
Returns `true` if all checks pass, or `false` on failure (with diagnostic output printed
to stderr).

# Check macros

Use these macros inside the `@filecheck` block to specify directives:

- `@check "pattern"` — Match `pattern` anywhere after the previous match.
- `@check_next "pattern"` — Match `pattern` on the line immediately following the previous match.
- `@check_same "pattern"` — Match `pattern` on the same line as the previous match.
- `@check_label "pattern"` — Like `@check`, but resets the match context, useful for dividing checks into independent sections.
- `@check_not "pattern"` — Verify that `pattern` does *not* appear between the surrounding matches.
- `@check_dag "pattern"` — Match `pattern` in any order relative to other `@check_dag` directives.
- `@check_empty "pattern"` — Verify that the next line is empty.
- `@check_count n "pattern"` — Match `pattern` exactly `n` times.

Each check macro also accepts these keyword arguments:

- `literal=true`: Insert the `{LITERAL}` modifier, disabling regex matching.
- `cond=expr`: Only include this check directive when `expr` evaluates to `true` at runtime.

# Keyword arguments

These are forwarded to LLVM's FileCheck as CLI flags:

- `match_full_lines::Bool`: Require matches to span entire lines (`--match-full-lines`).
- `strict_whitespace::Bool`: Disable default whitespace canonicalization (`--strict-whitespace`).
- `ignore_case::Bool`: Case-insensitive matching (`--ignore-case`).
- `implicit_check_not::Union{String,Vector{String}}`: Fail if the given pattern(s) appear
  anywhere in the input (`--implicit-check-not`).
- `enable_var_scope::Bool`: Enable scoping for FileCheck variables (`--enable-var-scope`).
- `dump_input::String`: Control input dump on failure, e.g. `"always"` or `"fail"` (`--dump-input`).
- `verbose::Bool`: Show successful match details (`-v`).
- `very_verbose::Bool`: Show all match attempts (`-vv`).
- `check_prefixes::Vector{String}`: Use custom check prefixes (`--check-prefixes`).
- `defines::Dict{String,String}`: Define FileCheck variables (`-Dkey=value`).
- `allow_empty::Bool`: Allow empty check files (`--allow-empty`).

# Examples

```julia
using Test

@test @filecheck begin
    @check "hello"
    print("hello world")
end

@test @filecheck match_full_lines=true begin
    @check "hello world"
    print("hello world")
end

@test @filecheck begin
    @check literal=true "foo {{bar}}"
    print("foo {{bar}}")
end
```
"""
macro filecheck(args...)
    # Separate kwargs from the body expression
    ex = args[end]
    macro_kwargs = args[1:end-1]

    ex = Base.macroexpand(__module__, ex)
    if isempty(checks)
        error("No checks provided within the @filecheck macro block")
    end
    collected = copy(checks)
    empty!(checks)

    # Build runtime code to conditionally collect check lines
    stmts = Expr[:(local _checks = String[])]
    for (cond, literal, name, pattern) in collected
        literal_str = literal ? "{LITERAL}" : ""
        directive = "$name$literal_str: $pattern"
        if cond === nothing
            push!(stmts, :(push!(_checks, $directive)))
        else
            push!(stmts, :(if $(cond); push!(_checks, $directive); end))
        end
    end
    push!(stmts, :(local _check_str = join(_checks, "\n")))

    # Build kwargs to forward to filecheck()
    fc_kwargs = parse_kwargs(macro_kwargs)
    kw_exprs = [Expr(:kw, k, v) for (k, v) in fc_kwargs]

    esc(quote
        $(stmts...)
        $filecheck(_check_str; $(kw_exprs...)) do _
            $ex
        end
    end)
end

end # module FileCheck
