module FileCheck

import LLVM_jll

export filecheck, @filecheck
export @check, @check_label, @check_next, @check_same
export @check_not, @check_dag, @check_empty, @check_count

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

function filecheck(f, input)
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
        proc = run(pipeline(ignorestatus(cmd); stdin=IOBuffer(output), stdout=filecheck_io, stderr=filecheck_io); wait=false)
        close(filecheck_io.in)

        # collect the output of FileCheck
        reader = Threads.@spawn String(read(filecheck_io))
        Base.wait(proc)
        log = strip(fetch(reader))

        # error out if FileCheck did not succeed.
        # otherwise, return true so that `@test @filecheck` works as expected.
        if !success(proc)
            error(log)
        end
        return true
    end
end

# collect checks used in the @filecheck block by piggybacking on macro expansion
const checks = Tuple{Any,String}[]

function _parse_check_args(args)
    str = args[end]
    kwargs = Dict{Symbol,Any}()
    for kwarg in args[1:end-1]
        if kwarg isa Symbol
            kwargs[kwarg] = kwarg
        elseif Meta.isexpr(kwarg, :(=))
            kwargs[kwarg.args[1]] = kwarg.args[2]
        else
            throw(ArgumentError("Invalid keyword argument '$kwarg'"))
        end
    end
    return kwargs, str
end

function _parse_check_count_args(args)
    str = args[end]
    n = args[end-1]
    kwargs = Dict{Symbol,Any}()
    for kwarg in args[1:end-2]
        if kwarg isa Symbol
            kwargs[kwarg] = kwarg
        elseif Meta.isexpr(kwarg, :(=))
            kwargs[kwarg.args[1]] = kwarg.args[2]
        else
            throw(ArgumentError("Invalid keyword argument '$kwarg'"))
        end
    end
    return kwargs, n, str
end

macro check(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK: $str"))
    nothing
end

macro check_label(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-LABEL: $str"))
    nothing
end

macro check_next(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-NEXT: $str"))
    nothing
end

macro check_same(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-SAME: $str"))
    nothing
end

macro check_not(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-NOT: $str"))
    nothing
end

macro check_dag(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-DAG: $str"))
    nothing
end

macro check_empty(args...)
    kwargs, str = _parse_check_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-EMPTY: $str"))
    nothing
end

macro check_count(args...)
    kwargs, n, str = _parse_check_count_args(args)
    cond = get(kwargs, :cond, nothing)
    push!(checks, (cond, "CHECK-COUNT-$n: $str"))
    nothing
end

macro filecheck(ex)
    ex = Base.macroexpand(__module__, ex)
    if isempty(checks)
        error("No checks provided within the @filecheck macro block")
    end
    collected = copy(checks)
    empty!(checks)

    # Build runtime code to conditionally collect check lines
    stmts = Expr[:(local _checks = String[])]
    for (cond, directive) in collected
        if cond === nothing
            push!(stmts, :(push!(_checks, $directive)))
        else
            push!(stmts, :(if $(cond); push!(_checks, $directive); end))
        end
    end
    push!(stmts, :(local _check_str = join(_checks, "\n")))

    esc(quote
        $(stmts...)
        filecheck(_check_str) do _
            $ex
        end
    end)
end

end # module FileCheck
