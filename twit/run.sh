#!/bin/sh
erlc twit.erl
echo 'l(twit).
A = twit:create("alice", "alicepass").
io:format("~n### REGISTERED ALICE ###~n").
B = twit:create_and_join(A, "bob", "bobpass").
io:format("~n### REGISTERED BOB ###~n").
C = twit:create_and_join(B, "charlie", "charliepass").
io:format("~n### REGISTERED CHARLIE ###~n").
io:format("~n### WAITING FOR RING TO STABILIZE ###~n").
timer:sleep(1000).
io:format("~n### ALICE GETS BOBS TIMELINE ###~n").
twit:timeline(A, "bob").
io:format("~n### ALICE POSTS A MESSAGE ###~n").
twit:post(A, "i am bored", "alicepass").
timer:sleep(1000).
io:format("~n### ALICE POSTS ANOTHER MESSAGE ###~n").
twit:post(A, "distributed systems are hard!", "alicepass").
io:format("~n### BOB POSTS A MESSAGE ###~n").
twit:post(B, "bob is cool", "bobpass").
io:format("~n### CHARLIE POSTS A MESSAGE ###~n").
twit:post(C, "i am having fun", "charliepass").
io:format("~n### CHARLIE GETS BOBS TIMELINE ###~n").
twit:timeline(C, "bob").
io:format("~n### SOMEONE ATTEMPTS TO POST TO BOBS TIMELINE WITHOUT THE CORRECT PASSWORD ###~n").
twit:post(B, "bob is stupid", "notbobpass").
io:format("~n### CHARLIE GETS BOBS TIMELINE AGAIN ###~n").
twit:timeline(C, "bob").
io:format("~n### CHARLIE GETS ALICES TIMELINE ###~n").
twit:timeline(C, "alice").
' | erl
