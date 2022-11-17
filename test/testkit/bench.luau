----------------------------------------------------------------------
-- testkit/bench.lua
----------------------------------------------------------------------

local benchData: {
    timing: boolean,
    time: number,
    start: number?,
    iterations: number?
}?

local START = function(iter: number?): number?
    assert(benchData, "no active benchmark")
    assert(not benchData.start, "clock was already started")
    assert(not iter or iter and not benchData.iterations, "cannot change iteration count")
    benchData.timing = true
    benchData.iterations = iter
    benchData.start = os.clock()
    return iter
end :: ((iter: number) -> number) & (() -> ())

local function STOP(iter: number?): number
    local stop = os.clock()
    assert(benchData, "no active benchmark")
    assert(benchData.start, "clock was already stopped")
    assert(not iter or iter and not benchData.iterations, "cannot change iteration count")
    benchData.timing = false
    if iter then benchData.iterations = iter end
    local duration = stop - benchData.start
    benchData.time += duration
    return duration
end

local function ITER(iter: number)
    assert(benchData, "no active benchmark")
    assert(iter and not benchData.iterations, "cannot change iteration count")  
    benchData.iterations = iter
end

local function BENCH(name: string, fn: () -> ())
    assert(not benchData, "cannot run benchmark, a benchmark is already in progress")
    local r = {
        timing = false,
        time = 0
    }; benchData = r

    local start = os.clock()

    fn()

    local stop = os.clock()
    assert(benchData, "benchdata missing")

    if benchData.time == 0 then
        if not benchData.start then -- implicit start and stop
            benchData.time += stop - start   
        else -- implicit stop
            benchData.time += stop - benchData.start
        end
    end

    print(string.format("[%.3f μ] %s", benchData.time / (benchData.iterations or 1) * 1e6, name))

    benchData = nil
end

return function()
    return BENCH, START, STOP, ITER
end

