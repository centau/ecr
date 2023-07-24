# Entity Identifiers

In ECS, an "entity" is just an abstract thing to mentally associate components
with. In implementation, an entity identifier is just a key used to access
internal storage of components.

They can be thought of as pointers but with extra safety checks.

Ids must be able to uniquely identify entities, that is no two entities can
exist with the same id at the same time.

## Simple Approach

A simple implementation would be to keep track of a counter; each time a new
entity is created, this counter is incremented and its value returned as a new
id. There would be no concern for the counter overflowing either. Numbers in
Luau are represented using 64-bit floats which can represent `2^64`, i.e.
`1.8446744e+19` unique values, making it very difficult (impossible?) to
overflow.

This approach has drawbacks, however. Using these ids as an array index will
result in steady-growth of memory usage as you create more and more ids as the
arrays must grow to fit the largest id. You can solve this by using a hashmap
instead which does not need to grow with the largest id, but this sacrifices
speed to save memory usage, as hashing is much slower than array indexing.

> todo: add benchmark

## ECR's Approach

ECR splits ids into 2 parts using bit manipulation.
The lower part is called the *key* and the upper part is called the *version*.

The key part is used as an array index and can be reused when other entities are
destroyed and their keys become free.

The version part is used to keep the *overall* id unique. If we only used the
key part as the entire id, we run into issues with storing ids of dead entities,
and having new entities reusing the exact same id, resulting in being unable to
differentiate between a dead entity and an alive entity. So each time a new
entity reuses a key, the version part of the id is incremented so that the
overall id remains unique.

Example using 8-bit ids with 4 bits for the key and 4 bit for the version:

```lua
0001 0001 = 17 -- id with key = 1, version = 1
0010 0001 = 33 -- id with key = 1, version = 2
0001 0010 = 18 -- id with key = 2, version = 1
```

Notice how despite reusing a key, we can keep overall ids unique by separating
the id into key and version parts.

### Tracking Unused Keys

There are a few ways to keep track of unused keys for reuse. One way is to use a
stack to track unused keys, pushing onto the stack when an entity is destroyed
and popping from the stack when a new entity is created. ECR instead uses an
array with a linked-list built into it.

Each index of the array corresponds to a key `k` (`array[k]` corresponds to key
`k`).

<details>
  <summary>Implementation</summary>

---

Say we have a function `ID(key, version)` which creates an id using the given
key and version.

When key `k` is in use, `array[k] = ID(k, v)` where
`v` is how many times that key has been used.

When key `k` is not in use, `array[k] = ID(k_next, v)` where
`k_next` is the *next key not in use* or `0`, that is, a pointer to the next
free key or nothing,
and `v` is still how many times key `k` has been used.

We keep track of the head of the list using a variable `head` that holds the
first unused key. If an unused key `k` is at the tail of the list, then
`array[k] = ID(0, v)`. A key can never be `0` (arrays in Luau start at 1) so
we use `0` to signify nothing. If the list is empty then `head` is set to `0`.

When we want to create a new id, we check if `head ~= 0`. If `head == 0` then
we just create a brand new key `#array + 1`. Otherwise, we know that we have an
unused key `k` where `head = k`. We know that `array[k] = ID(next_k, v)`.
So we set `head = next_k` and set `array[k] = ID(k, v)` and return `ID(k, v)`.

When we want to destroy an id with key `k` we do `array[k] = ID(head, v+1)`
and set `head = k`.

Difficult to grasp at first but the advantage of this approach is that we can
quickly see if a given key is in use or not instead of searching through a stack
of unused keys, as well as only needing a single array index for each entity,
since both key and version are stored at the one index.

---

</details>

### Bit Manipulation and Floats

In Luau, numbers are 64-bit floating points. The format for these floats are
specified in the IEEE-754 standard. Due to how these floats work, they can
perfectly represent any 53-bit integer with no rounding issues. ECR splits the
53 bits `[19:0]` for the key and `[52:20]` for the version.

Extracting the lower 20 bits to get the key is done with a single bitwise `AND`
operation (`bit32.band(id, mask)`) with a 20-bit bitmask
(a very fast operation). As the `bit32` library only works with the lower 32
bits, we cannot access bits `[52:20]` directly. We must instead shift the upper
bits down by 20 places via division by a power of 2.

Creating an id and getting the key and version of an id looks like:

```lua
local KEY_MASK = 2^20 - 1
local LSHIFT = 2^20
local RSHIFT = 1 / LSHIFT

local function ID_CREATE(key, version)
    return version * LSHIFT + key
end

local function ID_KEY(id)
    return bit32.band(id, KEY_MASK)
end

local function ID_VERSION(id)
    return (id - ID_KEY(id)) * RSHIFT
end
```

Some things to note are:

- instead of diving by a power of 2, we multiply by the reciprocal of a power of
  2 as multiplication is faster than division.

- to extract the version we first do `id - ID_KEY(id)` before shifting, so that
  the lower bits become all `0`s. If we skip this step, then the key part would
  become a fraction which introduces floating point rounding errors, making it
  so we can no longer recover the version accurately.

Using 20 bits for the key part gives us `2^20 - 1 = 1,048,575` keys (we can't
use 0) which is why that is the limit of the amount of entities you can create
at once.

Using 33 bits for the version part gives us `2^33 - 1 = 8,589,934,592` versions
(we start versions at 1) so each key can be reused over 8 billion times.

In the unlikely case that a key has been reused that many times, the key is
permanently deprecated and will not be reused again (as simple as not adding
the key back to the head of the list when it is removed).
