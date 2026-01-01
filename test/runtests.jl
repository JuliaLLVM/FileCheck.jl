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

end  # @testset "FileCheck"
