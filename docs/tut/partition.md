# Partitions

Currently, a registry by default can create entities occupying a range
between [1, 65534].
You can optionally restrict this range to avoid id conflicts when copying
entities from one registry to another.

The most common example of this is replicating server entities into a client
registry, while also being able to create client entities. The partitions can be
set up like so:

```lua
local server_registry = ecr.registry(1, 1000)
local client_registry = ecr.registry(1001, 2000)
```

This ensures that ids returned by `registry:create()` will never overlap. You
can still create entities outside of the range with an explicit
`registry:create(id)`.
