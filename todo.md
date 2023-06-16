# To do

List of things I would like to do with the library:

- Look into providing a flexible system scheduler
  - Splits frame into phases where certain components are added in one phase so
    that systems ran in the next phase know that entities operated on will have
    the needed components.
  - Allows scheduling of systems every frame or every x frames.
  - Automatic profiling.
  - Automatic error handling and better reporting.
- Look into component relationships
  - `ecr.pair(A, B)` to create new combinational component.
- Look into tags (value-less components for better memory efficiency)
  - Is this even worth implementing when it only saves 16 bytes per entity?
- More flexible observer API
  - Specify way to listen to only certain events (e.g. added or/and removed)
  - Is this even needed given that you can create custom observers already?
- Make `Registry:patch()` invoke constructor if no component is found.
  - Is there a case where this behavior is not wanted?
- Methods for bulk operations with entities and components
- Make `Registry:release()` safe
  - This is very hard to do performantly.
- Make grouping completely safe
  - Specifically, the case where an entity gets a component needed to add
    it to the group during view iteration led by a component owned by the same
    group.
  - Try to detect this at the end of iteration and raise an error.
- Improve docs
- Optimize entity destruction
  - The O(n) check for all registered components is perturbing when in large
  amount.
  - Potential for parallelized checks?
  - Defer destruction to end of frame and perform bulk removal?
  - Track the components an entity has using a bitset?
  - Archetypal tracking?
- Allow `nil` component values?
  - Could improve memory usage for tags.
  - But could add ambiguity between `nil` components and not having the component at all.
  - How does this affect creating views and observers?
- Implement a form of dynamic tags
  - Similar to:
    - `Entt` storage partitioning
    - `Flecs` entities as components
- Make methods like `Registry:has()` and `Registry:try_get()` error when invalid entities are passed
  - Should they?
  entities are used?
- Address behavior regarding adding to observers/queues during iteration
  - Currently newly added values are not returned during iteration, additionally
    clearing the observer/queue when iteration is completed means that any value
    that was added during iteration will not be returned the next time it is
    iterated. Is this the desired behavior?
- Also address behavior regarding clearing during iteration.
  - Currently should cause an error when it attempts to get the next element.
- Remove `version()` and `current()`
  - Id versioning is an implementation detail that I don't want to expose
- Refactor and cleanup the codebase.
- Decide if entities should be referred to as `ids` or `entities` in the docs and API.
