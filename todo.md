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
- Add entity handles
- Look into tags (value-less components for better memory efficiency)
  - Is this even worth implementing when it only saves 16 bytes per entity?
- More flexible observer API
  - Specify way to listen to only certain events (e.g. added or/and removed)
  - Is this even needed given that you can create custom observers already?
- Make `Registry:get()` error if entity does not have component
- Add `Registry:try_get()` which has behavior of current get
- Make `Registry:patch()` invoke constructor if no component is found.
- Add a queue class for efficient queuing
- Add method for naming components for debugging
  - `function ecr.name(Map<string, Component>)`?
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
  - But could add ambiguity between `nil` components and not having the component
  at all.
- Implement a form of dynamic tags
  - Similar to:
    - `Entt` storage partitioning
    - `Flecs` entities as components
