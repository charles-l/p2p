#!/bin/sh
erlc chord.erl
echo 'l(chord).
[R|_] = chord:spawn_ring(10).
io:format("Waiting for ring to stabilize...\n").
timer:sleep(6200).
io:format("=== INSERTING KEYS ===\n").
chord:insert(R, "the key", "the val").
chord:insert(R, "another key", "another val").
chord:insert(R, "yet another key", "yet another val").
chord:insert(R, "moar key", "moar val").
chord:insert(R, "and a final key", "a final val").
io:format("=== INSERTING KEYS ===\n").
chord:lookup(R, "the key").
chord:lookup(R, "yet another key").
chord:lookup(R, "and a final key").' | erl
io:format("=== FINISHED ===\n").
