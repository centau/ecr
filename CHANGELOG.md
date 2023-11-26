# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## Unreleased

### Added

- Constant `ecr.context`.
- Function `ecr.copy_array_to_buffer()`.
- Function `ecr.copy_buffer_to_array()`.

### Changed

- All components must be defined before the registry using them is created.
- Renamed `ecr.Entity` type alias to `ecr.entity`.
- Property `Pool.entities` is now a `buffer`.
- The context entity does not exist until `Registry:context()` is first called.
- Renamed `Registry:removing()` to `Registry:removed()`.
- Observers are now empty when first created.
- Method `Observer:disconnect()` can only be called on empty observers.
- Signal `Registry:changed()` now fires *before* the component is changed.
  - New value still given as argument, but now can retrive old value with `Registry:get()`.

### Improved

Large refactor to use the new Luau `buffer` datatype. Up to 2x faster and 2-4x
less memory usage across the board.

---

## [0.7.0] - 2023-07-20

### Added

- `Connection:reconnect()`.
- `ecr.entity` which is a built-in component that can be used to access a
  dedicated entity pool:
  - Exclude-only views `registry:view(ecr.entity):exclude(...)`.
  - Signals for creation and destruction of entities `registry:added(ecr.entity):connect()`.
  - Direct access to array of all entities in the registry `registry:storage(ecr.entity)`.
- `ecr.is_tag()` to check if a given component is a tag type.
- `Registry:context()` to store components not specific to an entity.
- Methods for lower level access to pools.

### Changed

- Using `Registry:set()` to set `nil` values will now error.
  - Use `Registry:remove()` instead.
- `Registry:handle()` calls are now memoized, passing the same ids will return
  the same handle objects.

### Removed

- Operations `#Registry` and `for id in Registry do`.
  - Replaced by entity storage.

---

## [0.6.1] - 2023-07-04

### Changed

- `Registry:patch()` will invoke the component constructor if the entity does
  not have the given component.

### Fixed

- `Registry:orphaned()` not erroring with destroyed id.
- `ecr.queue()` clearing early.

---

## [0.6.0] - 2023-06-27

### Added

- Check for iterator invalidation occuring with group misusage.
- Function `ecr.tag()` to create valueless components.
- Function `ecr.queue()` and the `Queue` class.
- Function `ecr.name()` for associating names with component types.
- Method `Registry:handle()` and the `Handle` class.
- Method `Registry:try_get()`.
- Method `Observer:persist()`.
- Length operator for registry `#Registry`.
- Iteration over registry `for id in Registry do`.

### Changed

- Observers will automatically clear themselves after iteration by default.
  - Call `Observer:persist()` to stop this.
- `Registry:get()` will now error if the entity does not have every component.

### Removed

- Method `Registry:version()`.
- Method `Registry:current()`.
- Method `Registry:entities()`.
- Method `Registry:size()`.

---

## [0.5.0] - 2023-05-14

### Changed

- Connecting or disconnecting an already connected or disconnected observer will no longer error.
- Excluding an already excluded component with `View:exclude()` and `Observer:exclude()` no longer errors.
- Method `Registry:add()` will do nothing if the entity already has the component.
- Method `Registry:orphan()` renamed to `Registry:orphaned()`.
- Method `Registry:valid()` renamed to `Registry:contains()`.
- Method `Registry:create()` is now guaranteed to always return unique identifiers.
- Using invalid entities no longer causes undefined behavior in any method and instead errors.
- `Registry:track()` will now track all components passed, not just the first one.

### Removed

- Methods:
    - `View:each()`
    - `Observer:each()`
    - `Group:each()`

## Fixed

- Undefined behavior sometimes occuring when removing grouped components.
- Observers not returning up-to-date values when changing a component while it is disconnected.

---

## [0.4.0] - 2023-01-26

### Added

- Component grouping and `Registry:group()`.
- Method `View:use()`.
- Constant `ecr.null`.

### Removed

- Method `View:include()` and `Observer:include()`.

### Fixed

- `Registry:add()` not firing `Registry:added()` signals.
- Mismatch between argument list and values returned in multi-typed observers.
- Observers not garbage collecting after calling `Observer:disconnect()`.

### Improved

- Connection firing speed by ~70%.

---

## [0.3.0] - 2023-01-09

### Added

- Overload for `Registry:create()` to create an entity with a given identifier.

### Changed

- Registry signals no longer pass the registry as the first argument to listeners.
- Observers no longer track entities with removed components.
- Method `Registry:entities()` now creates and returns an array of only valid entities.
- Function `ecr.registry()` can no longer pre-allocate memory.

### Removed

- Method `Registry:capacity()`.

### Improved

- Double-type view iteration speed by ~100%.

---

## [0.2.0] - 2022-12-08

### Added

- Method `View:include()` and `Observer:include()`.
- Method `Registry:patch()`.
- Method `Registry:add()` and optional default parameter for `ecr.component()`.

### Changed

- Behavior `for ... in View do` now behaves the same as `for ... in View:each() do`.
- Signal diconnect API (Signal now returns a connection object to call disconnect on).

### Improved

- Entity creation and release speed by ~100%.
- Multi-type view iteration speed by ~60%.

## [0.1.0] - 2022-11-16

- Initial release.
