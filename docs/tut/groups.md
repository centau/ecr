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
entity.

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

## Limitations

- As mentioned before, each component type can only be owned by one group,
  groups cannot share components so you need to profile to determine where the
  most benefit is gained.

- In a rare case, causing an entity to join a group during iteration of a view
  with a group-owned component, will invalidate the view iterator.
  
  This is due to how groups organise their components in memory. This can be
  avoided if you:
    1. queue the entities to add components later, instead of during iteration.
    2. know that adding those group-owned components will not cause the entity
       to enter the group.

Views can detect and will error if the above rules are broken so you do not need
to worry about it until it happens.

## When to group

While views are fast, in certain situations like where a view contains many
components, iteration of a view may be the bottleneck of a system.
In such cases, by grouping components together, iteration becomes as fast as
possible at the cost of the above limitations.

You should only use grouping when you have profiled and identified that the
iteration of a view is the bottleneck of a system.
