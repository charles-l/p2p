# Design

Generate a ring a ring:
* Spawn a ring of nodes, each which knows the pid of the next node (basically a circular linked list)
* Generate an hash (referred to as the id) for every node in the server.
* Sort the ring by hash

To insert a key, value pair:
* Hash the key
* Find which two nodes it fits between (based on id).
* Insert it into the hash table for the node with the lower id

To lookup a key:
* Hash the key
* Find which two nodes it fits between (based on id)
* Look it up in the hash table for the node with the lower id

# Lessons learned

* Distributed applications are hard (especially from a timing and ordering perspective)
* A simple DHT can be implemented as a linked list of buckets

# Use case

A DHT can be used to make a redundent data store that has a simple interface of appearing to be a regular hash table
