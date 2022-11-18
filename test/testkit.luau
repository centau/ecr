----------------------------------------------------------------------
-- testkit.luau
-- v0.1.0
----------------------------------------------------------------------

--!strict

----------------------------------------------------------------------
-- Unit Testing
----------------------------------------------------------------------

type Test = {
    name: string,
    activeCase: Case?,
    cases: { Case },
    duration: number,
    error: string?
}

type Case = {
    name: string,
    result: number,
    line: number?
}

local PASS = 1
local FAIL = 2
local NONE = 3
local ERROR = 4

local activeTest: Test?
local tests: { Test } = {}

local function outputTestResults(test: Test)
    print("\27[1;4m"..test.name.."\27[0m")
    for _, case in test.cases do
        print(
            "[" ..
            (if case.result == PASS then
                "\27[32;1mPASS\27[0m"
            elseif case.result == FAIL then
                "\27[31;1mFAIL:"..assert(case.line).."\27[0m"
            elseif case.result == NONE then  
                "\27[33;1mNONE\27[0m"
            else
                "\27[41;1;30mERROR\27[0m")
            .. "] " .. case.name
        )
    end

    if test.error then
        print("\27[31;1;30merror: " .. test.error .. "\27[0m")
    end

    print ""
end

local function TEST(name: string, fn: () -> ())
    assert(not activeTest, "new test was started while a test was in progress")
    local test: Test = {
        name = name,
        cases = {},
        duration = 0
    }

    activeTest = test
    table.insert(tests, test)

    local start = os.clock()
    local success, msg: string? = pcall(fn)
    test.duration = os.clock() - start

    assert(test.activeCase, "empty test")

    if not success then
        test.activeCase.result = ERROR
        test.error = msg
    end

    activeTest = nil
    outputTestResults(test)
end

local function CASE(name: string)
    assert(activeTest, "no active test")

    local case: Case = {
        name = name,
        result = NONE
    }

    activeTest.activeCase = case
    table.insert(activeTest.cases, case)
end

local function CHECK(value: any)
    assert(activeTest, "no active test")
    local activeCase = activeTest.activeCase

    if not activeCase then
        CASE ""
        activeCase = activeTest.activeCase
    end; assert(activeCase, "no active case")

    if activeCase.result == NONE or activeCase.result == PASS then
        activeCase.result = value and PASS or FAIL
        activeCase.line = debug.info(2, "l")
    end
end

local function FINISH(): boolean
    local success = true
    local totalCases = 0
    local passedCases = 0
    local duration = 0

    for _, test in tests do
        duration += test.duration
        for _, case in test.cases do
            totalCases += 1
            if case.result == PASS or case.result == NONE then
                passedCases += 1
            else
                success = false
            end
        end
    end

    print(string.format("%d/%d test cases passed in %.3f ms.", passedCases, totalCases, duration*1e3))

    local fails = totalCases - passedCases

    print(string.format("\27[%d;1;30m%d fail%s\27[0m", fails > 0 and 41 or 42, fails, fails == 1 and "" or "s"))

    return success, table.clear(tests)
end

----------------------------------------------------------------------
-- Benchmarking
----------------------------------------------------------------------

type Bench = {
    timeStart: number?,
    memStart: number?,
    iterations: number?
}

local activeBench: Bench? = nil

function START(iter: number?): number
    local n = iter or 1
    if n < 1 then error("iteration count must be greater than 0", 2) end
    assert(activeBench, "no active benchmark")
    assert(not activeBench.timeStart, "clock was already started")

    activeBench.iterations = n
    activeBench.memStart = gcinfo()
    activeBench.timeStart = os.clock()
    return n
end

local function BENCH(name: string, fn: () -> ())
    assert(not activeBench, "cannot run benchmark, a benchmark is already in progress")

    local bench: Bench = {}
    activeBench = bench

    local memStart = gcinfo()
    local timeStart = os.clock()
    local success, msg: string? = pcall(fn)
    local timeStop = os.clock()
    local memStop = gcinfo()

    if not success then
        print("[\27[41;1mERROR\27[0m] " .. name)
        print("\27[31;1m" .. "error: " .. msg :: string .. "\27[0m")
        activeBench = nil
        return
    end

    timeStart = bench.timeStart or timeStart
    memStart = bench.memStart or memStart

    local n = bench.iterations or 1
    local duration = timeStop - timeStart
    local allocated = memStop - memStart

    print(string.format("[ %.3f us | %4.0f B ] %s", duration/n * 1e6, allocated/n * 1e3, name))

    activeBench = nil
end

----------------------------------------------------------------------
-- Return
----------------------------------------------------------------------

return {
    getUnitTestTools = function()
        return TEST, CASE, CHECK, FINISH
    end,

    getBenchmarkTools = function()
        return BENCH, START
    end
}
