# Design

[Whitepaper](https://en.wikipedia.org/wiki/Chord_(peer-to-peer))

The chord protocol is similar to a basic ring with a "finger table" so lookups end up being O(log(N)) rather than O(N).

Also, new nodes can join at any point on the ring, and the ring will eventually self stabilize.

The finger table stores the 2^(i + 1)-th node's ID and address, so inserts/lookups end up looking like a binary, where the node finds the nearest next node to forward to.

# Lessons learned

* Dealing with deadlocks was difficult, so passing async messages ended up being the best solution in most cases.
* Stabilization can be achieved simply

# Use case

The chord ring is a better design than the simple DHT ring I implemented, because it is faster, and is better at self-stabilizing.
