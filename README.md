<br>

<div align="center">
    <img src="docs/logo.svg" width="600" />
</div>

<br>

#

<br>

ECR is a pure Luau ECS library.

- Uses Luau typechecking
- A library and not a framework
- Cache friendly sparse-set based storage that can support perfect SoA.
- Carefully optimized memory usage and performance.
- Signals and observers for detecting changes to components.
- Also provides utilities for common practices such as queuing events.

## Getting started

Read the [crash course](https://centau.github.io/ecr/tut/crashcourse) for a
brief introduction to the library.

## Code sample

```lua
local ecr = require(ecr)

local world = ecr.registry()

local Health = ecr.component(function() return 100 end)
local Position = ecr.component(Vector3.new)
local Velocity = ecr.component(Vector3.new)

local id = world:create()
world:add(id, Health, Position, Velocity)

local function updatePhysics(dt: number)
    for id, position, velocity in world:view(Position, Velocity) do
        world:set(id, Position, position + velocity * dt)
    end
end

local function regenHealth(dt: number)
    for id, health in world:view(Health) do
        world:set(id, health + 1 * dt)
    end
end
```
