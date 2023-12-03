<br>

<div align="center">
    <img src="docs/public/logo.svg" width="600" />
</div>

<br>

#

<br>

### ⚠️ This library is in early stages of development with breaking changes being made often.

ECR is a Luau ECS library.

- A library and not a framework
- Uses typechecking.
- Sparse-set based storage that can support perfect SoA.
- Carefully optimized memory usage and performance.
- Signals for detecting changes to components.

## Getting started

Read the [crash course](https://centau.github.io/ecr/tut/crash-course) for a
brief introduction to the library.

## Code sample

```lua
local ecr = require(ecr)

-- define components
local Position = ecr.component() :: Vector3
local Velocity = ecr.component() :: Vector3

-- define a system
local function update_physics(world: ecr.Registry, dt: number)
    for id, pos, vel in world:view(Position, Velocity) do
        world:set(id, Position, pos + vel*dt)
    end
end

-- instantiate the world
local world = ecr.registry()

-- create entities and assign components
for i = 1, 10 do
    local id = world:create()
    world:set(id, Position, Vector3.new(i, 1, 1))
    world:set(id, Velocity, Vector3.new(10, 0, 0))
end

-- run system
update_physics(world, 1/60)
```
