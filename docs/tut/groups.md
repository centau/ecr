# Groups

Groups are a technique used to optimize iteration over a set of component types.
Groups achieve perfect [SoA](https://en.wikipedia.org/wiki/AoS_and_SoA) for the
best iteration performance at the cost of more expensive addition and removal of
group-owned components.

## Creation

Groups can be created as followed:

```lua
registry:group(A, B, C)
```

This creates a new group with components `A`, `B` and `C`.
These 3 components are now said to be *owned* by the group.

Each component type can only be owned by a single group. The following code
would result in an error:

```lua
registry:group(A, B)
registry:group(B, D)
```

This errors because 2 different groups cannot claim ownership of `B`.

Groups do not have to be stored aside when they are created, the first time a
group is created it is stored permanently inside the registry, future
`registry:group()` calls will just return the same group for the same set of
components.

Once a group is created, it will ensure that its owned components are aligned
with each other in memory whenever a component is added or removed from an
entity. This means the only performance cost grouping imposes is the addition
and removal of group-owned components on entities. Changing the values
of already added group-owned components is unaffected.

## Usage

A group is iterated in the same way as a view.

```lua
for id, position, velocity in registry:group(Position, Velocity) do
    registry:set(id, Position, position + velocity*dt)
end
```

Components can be added, changed and removed during iteration.

The exact size of a group can also be read:

```lua
local size = #registry:group(A, B)
```

## Perfect SoA

Since groups guarantee alignment of its owned components, they can be modified
together directly.

```lua
local Position = ecr.component(Vector3.new)
local Velocity = ecr.component(Vector3.new)

local function update_positions(dt: number)
    local n = #registry:group(Position, Velocity)
    local positions = registry:storage(Position).values
    local velocities = registry:storage(Velocity).values

    for i = 1, n do
        positions[i] += velocities[i] * dt
    end
```

It is important not to exceed the size of the group `n` or you will act on
entities outside of the group, where the `i`th component values may no longer
correspond with each other.

## Limitations

- As mentioned before, each component type can only be owned by one group,
  groups cannot share components so you need to profile to determine where the
  most benefit is gained.

- In a rare case, during the iteration of a view including a group-owned
  component, an entity joining the group because a group-owned component was
  added will invalidate the view iterator.
  
  This is due to how groups organise their components in memory. This can be
  avoided if you:
    1. defer adding components to after iteration instead of during iteration.
    2. know that adding those group-owned components will not cause the entity
       to enter the group.

Views can detect and will error if the above rules are broken so you do not need
to worry about it until it happens.

## When to group

While views are fast, in certain situations like where a view contains many
components, iteration of a view may be the bottleneck of a system.
In such cases, by grouping components together, iteration becomes as fast as
possible, removing the bottleneck.

You should only use grouping when you have profiled and identified that the
iteration of a view is a system bottleneck.
