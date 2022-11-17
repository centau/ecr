----------------------------------------------------------------------
-- testkit/unit.luau
----------------------------------------------------------------------

type Case = {
    name: string,
    result: boolean,
    line: number?
}

local TAB = "    "

local testData: {
    activeCase: Case?,
    cases: { Case }
}?

local PASS = "\27[102;93mPASS\27[0m"
local FAIL = "\27[101;93mFAIL\27[0m"

local function TEST(name: string, fn: () -> ())
    local function outputTestResults(test)
        print(name)
        for i, case in test.cases do
            if case.result == true then
                print(TAB.."["..PASS.."] "..case.name)  
            else
                print(TAB.."["..FAIL..":"..assert(case.line).."] "..case.name)
            end
        end
    end

    local r = {
        cases = {}
    }; testData = r

    --local ok, err: string? = pcall(fn)
    fn()

    assert(testData and testData == r, "new test was started while current test was in progress")
    assert(testData.activeCase, "no test cases")

    if testData.activeCase then table.insert(testData.cases, testData.activeCase) end
    outputTestResults(testData)
    testData = nil
end

local function CASE(name: string)
    assert(testData, "no active test")
    if testData.activeCase then
        table.insert(testData.cases, testData.activeCase)
    end
    testData.activeCase = {
        name = name,
        result = true
    }
end

local function CHECK(value: any)
    assert(testData, "no active test")
    local activeCase = testData.activeCase
    assert(activeCase, "no active case")

    if activeCase.result == true then
        activeCase.result = value and true or false
        activeCase.line = debug.info(2, "l")
    end
end

return function()
    return TEST, CASE, CHECK
end
