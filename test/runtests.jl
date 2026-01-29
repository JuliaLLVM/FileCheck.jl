using Test
using FileCheck

@testset "FileCheck" begin

@testset "@check basic" begin
    @test @filecheck begin
        @check "hello"
        "hello world"
    end

    @test @filecheck begin
        @check "first"
        @check "second"
        """
        first line
        second line
        """
    end
end

@testset "@check regex patterns" begin
    @test @filecheck begin
        @check "value = {{[0-9]+}}"
        "value = 42"
    end

    @test @filecheck begin
        @check "{{.*}}world"
        "hello world"
    end
end

@testset "@check_label" begin
    @test @filecheck begin
        @check_label "function foo"
        @check "body"
        @check_label "function bar"
        @check "other"
        """
        function foo:
          body here
        function bar:
          other stuff
        """
    end
end

@testset "@check_next" begin
    @test @filecheck begin
        @check "first"
        @check_next "second"
        """
        first line
        second line
        """
    end
end

@testset "@check_same" begin
    @test @filecheck begin
        @check "key"
        @check_same "value"
        "key = value"
    end
end

@testset "@check_not" begin
    @test @filecheck begin
        @check_not "error"
        "success"
    end

    @test @filecheck begin
        @check "start"
        @check_not "bad"
        @check "end"
        """
        start
        good
        end
        """
    end
end

@testset "@check_dag" begin
    # DAG checks can match in any order
    @test @filecheck begin
        @check_dag "apple"
        @check_dag "banana"
        """
        banana
        apple
        """
    end
end

@testset "@check_count" begin
    @test @filecheck begin
        @check_count 3 "repeated"
        """
        repeated
        repeated
        repeated
        """
    end
end

@testset "failure throws" begin
    @test_throws ErrorException @filecheck begin
        @check "missing pattern"
        "actual content"
    end

    @test_throws ErrorException @filecheck begin
        @check "first"
        @check_next "must be next"
        """
        first
        something else
        must be next
        """
    end
end

@testset "complex patterns" begin
    @test @filecheck begin
        @check_label "entry"
        @check "load"
        @check "add"
        @check "store"
        @check "return"
        """
        entry:
          %1 = load %ptr
          %2 = add %1, 1
          store %2, %ptr
          return
        """
    end
end

@testset "standard output" begin
    @test @filecheck begin
        @check "stdout"
        println("stdout")

        @check "stderr"
        println(stderr, "stderr")

        @check_not "bad"

        @check "result"
        "result"
    end
end

@testset "errors" begin
    @test_throws ErrorException("TestError") @filecheck begin
        @check_not "TestError"
        error("TestError")
    end
end

@testset "conditional checks" begin
    # cond=true: check is included
    @test @filecheck begin
        @check cond=true "hello"
        "hello world"
    end

    # cond=false: check is skipped, so no checks cause failure
    @test @filecheck begin
        @check "hello"
        @check cond=false "missing pattern"
        "hello world"
    end

    # cond with version comparison (always true)
    @test @filecheck begin
        @check cond=(VERSION >= v"0.0") "hello"
        "hello world"
    end

    # cond=false on @check_not: the NOT check is skipped entirely
    @test @filecheck begin
        @check "hello"
        @check_not cond=false "hello"
        "hello world"
    end

    # cond=false on @check_next: skipped, so non-adjacent line doesn't fail
    @test @filecheck begin
        @check "first"
        @check_next cond=false "second"
        """
        first line
        gap
        third line
        """
    end

    # cond=false on @check_label: skipped
    @test @filecheck begin
        @check "body"
        @check_label cond=false "nonexistent label"
        "body here"
    end

    # cond=false on @check_same: skipped
    @test @filecheck begin
        @check "key"
        @check_same cond=false "nonexistent"
        "key = value"
    end

    # cond=false on @check_dag: skipped
    @test @filecheck begin
        @check "hello"
        @check_dag cond=false "nonexistent"
        "hello world"
    end

    # cond=false on @check_empty: skipped
    @test @filecheck begin
        @check "hello"
        @check_empty cond=false "nonexistent"
        "hello world"
    end

    # cond=false on @check_count: skipped
    @test @filecheck begin
        @check "hello"
        @check_count cond=false 5 "hello"
        "hello world"
    end
end

@testset "match_full_lines" begin
    @test @filecheck match_full_lines=true begin
        @check "hello world"
        "hello world"
    end

    @test_throws ErrorException @filecheck match_full_lines=true begin
        @check "hello"
        "hello world"
    end
end

@testset "strict_whitespace" begin
    @test @filecheck strict_whitespace=true begin
        @check "hello  world"
        "hello  world"
    end
end

@testset "ignore_case" begin
    @test @filecheck ignore_case=true begin
        @check "hello"
        "HELLO"
    end
end

@testset "verbose" begin
    @test @filecheck verbose=true begin
        @check "hello"
        "hello world"
    end
end

@testset "enable_var_scope" begin
    @test @filecheck enable_var_scope=true begin
        @check_label "section1"
        @check "value = {{[0-9]+}}"
        @check_label "section2"
        @check "value = {{[0-9]+}}"
        """
        section1:
          value = 42
        section2:
          value = 99
        """
    end
end

@testset "defines" begin
    @test @filecheck defines=Dict("VAR"=>"42") begin
        @check "value = [[VAR]]"
        "value = 42"
    end
end

@testset "allow_empty" begin
    @test @filecheck allow_empty=true begin
        @check_not "error"
        ""
    end
end

@testset "implicit_check_not" begin
    @test @filecheck implicit_check_not="error" begin
        @check "hello"
        "hello world"
    end

    @test_throws ErrorException @filecheck implicit_check_not="world" begin
        @check "hello"
        "hello world"
    end

    # vector form
    @test @filecheck implicit_check_not=["error", "warning"] begin
        @check "hello"
        "hello world"
    end
end

@testset "literal" begin
    @test @filecheck begin
        @check literal=true "{{not a regex}}"
        "{{not a regex}}"
    end

    @test @filecheck begin
        @check "first"
        @check_next literal=true "[[not a var]]"
        """
        first
        [[not a var]]
        """
    end
end

end  # @testset "FileCheck"
