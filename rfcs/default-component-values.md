# Default Component Values

- Date - 2022/11/22
- Status - Under review

## Summary

This proposal adds a built-in way to specify a default value to be used when assigning a component to an entity.

## Motivation

It is common for components values to follow some sort of format, whose values may not be exactly known
at the time of assignment. Default values would allow a way to add components with a certain value automatically without the user having to at every point in the code where component assignment occurs.

This also creates a single source of truth for default values without extra machinery.

## Design

### API

This would be implemented with 2 new API changes:

- `ecr.component<T>(default: (() -> T)?): T`
- `Registry:add<T...>(entity, components: T...)`

The existing function `ecr.component()` will take an optional callback that produces a value to be assigned when a component is added using `Registry:add()`.

Because the user does not need to specify a value at the call site, this allows `Registry:add()` to take varargs and allow assignment of multiple components at the same time.

### Example

There are a few examples of how this makes assigning components easier:

1. Component "tags"

    A "tag" is known as a component that does not have a value. In practice the value `true` is usually assigned since `nil` cannot be, to represent the existance of the component.

    As of now, to assign tags one must do:

    ```lua
    registry:set(entity, TagA, true)
    registry:set(entity, TagB, true)
    ```

    This is tiresome, but with this proposal the following would be possible:

    ```lua
    registry:add(entity, TagA, TagB)
    ```

    This only requires the component to be defined as `local Tag = ecr.component(function() return true end)`.

2. Network ID

    Commonly in networking, there exists a "Network ID" component which stores unique IDs for replication of entity components.

    With default values, this could be implemented as follows:

    ```lua
    local id = 0
    local NetworkID = ecr.component(function()
        id += 1
        return id
    end)
    ```

    Any time `registry:add(entity, NetworkID)` is done, the id will automatically increment, eliminating the need for the user to add extra machinery to keep track of this.

### Misusage

- Using `registry:add(entity, A)` on an entity that already owns `A` would result in undefined behavior.

> Should it throw an error instead? This would require checking if the entity first owns the component before assigning it which adds a small performance penalty.

- Using `registry:add(entity, A)` when `A` was defined without specifying a callback `local A = ecr.component()` would result in an error.

> Alternatively we could have `registry:add()` calls with components with no default value instead default to assigning `true` (default default values??).

- Using a default value callback which returns `nil` will result in undefined behavior.

> Again, this could be changed to error instead on `Registry:add()` at the cost of slight performance.

## Drawbacks

None (?) asides from minor increase in API complexity.

## Alternatives

Keep things as are, users must explicitly specify a value for every component assigned or implement some sort of wrapper to do it for them.
