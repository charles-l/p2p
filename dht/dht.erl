% references:
%   + https://learnxinyminutes.com/docs/erlang/
%   + http://erlang-tutorials.colefichter.ca/dht1
%   + http://www.linuxjournal.com/article/6797
%   + http://erlang.org/doc/design_principles/gen_server_concepts.html
%   + http://learnyousomeerlang.com/clients-and-servers
%
% lessons learned:
%   + distributed applications are *hard*, especially to debug
%   + ensuring order is difficult
%     + gen_server helps with this
%       + handles synchronization with handle_call
%       + uniquely tags messages sent with handle_cast so processing is done on
%         the correct message

-module(dht).
-export([insert/3, lookup/2, spawn_ring/1, spawn_node/1, forward/3]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).
-behavior(gen_server).
-define(TIMEOUT, 3000). % global timeout for casts

-record(state, {
          next = nil, % next pid
          id = nil, % the server id
          tbl = nil % the servers local hashtable
}).

hashstr(S) -> % hash a string and return a string of the hash
    <<H:160/big-unsigned-integer>> = crypto:hash(sha, S),
    lists:flatten(io_lib:format("~40.16.0b", [H])).

genid() -> % convert IP address + pid into a hashed value (so each server gets a unique id)
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    hashstr(lists:flatten(io_lib:format("~p~p", [IpTuple, self()]))).

insert(Node, Key, Val) -> % generate insert call to add a key, value pair to the dht
    gen_server:cast(Node, {insert, hashstr(Key), Val}).

lookup(Node, Key) -> % generate a lookup call and wait for response
    K = hashstr(Key),
    gen_server:cast(Node, {lookup, K, self()}),
    Val = receive
              {lookup_for, K, R} -> R
          after ?TIMEOUT -> erlang:error(lookup_timeout)
          end,
    Val.

forward(Node, N, Msg) -> % generate a forward call to forward message around ring
    gen_server:cast(Node, {forward, N, Msg}).

spawn_ring(N) -> % spawn an initial ring of N servers (with buckets sorted)
    {ok, Head} = gen_server:start_link(?MODULE, #state{}, []),
    gen_server:call(Head, {set_next, Head}),
    lists:map(
      fun({_, X}) -> gen_server:call(X, {join_ring, Head}) end, % have each spawned server join the ring
      [gen_server:start_link(?MODULE, #state{}, []) || _ <- lists:seq(1, N)]), % spawn N servers
    Head.

spawn_node(Ring) -> % spawn a node and make it join the ring
    {ok, NewNode} = gen_server:start_link(?MODULE, #state{}, []),
    gen_server:call(NewNode, {join_ring, Ring}),
    NewNode.

% init function for gen_server behavior
init(S) -> {ok, S#state{id=genid(), tbl=dict:new()}}.
% terminate function for gen_server behavior
terminate(_, _) -> ok.

% determines if NewID should go between NodeID and NextID
% (handles edge case of ring wrap around)
is_between_buckets(NewID, NodeID, NextID) ->
    IsAtTail = NodeID > NextID,
    if
        ((NewID > NodeID) andalso (NewID < NextID)) orelse
        (IsAtTail andalso ((NewID < NextID) orelse (NewID > NodeID))) ->
            true;
        true ->
            false
    end.

% creates a find_bucket_pair call
% which walks around the Ring and checks whether the ID should be between
% the current and next node - when found, returns the pair of pids for the current
% and next node
find_bucket_pair(Head, ID, PID) ->
    gen_server:cast(Head, {find_bucket_position, ID, PID}),
    receive
        {target_pair, N, NN} -> {N, NN}
    after ?TIMEOUT ->
              {error, timeout}
    end.

% get the next nodes id
get_next_id(State) ->
    gen_server:call(State#state.next, {id}).

% get the id of the server
handle_call({id}, _From, State) ->
    {reply, State#state.id, State};
% get the pid of the next node
handle_call({next}, _From, State) ->
    {reply, State#state.next, State};
% update the pid for the next node
handle_call({set_next, N}, _From, State) ->
    {reply, ok, State#state{next = N}};
% join a ring starting at the head node
handle_call({join_ring, Head}, _From, State) ->
    case find_bucket_pair(Head, State#state.id, self()) of
        {error, timeout} ->
            {reply, timeout, State};
        {Node, NextNode} ->
            gen_server:call(Node, {set_next, self()}),
            io:format("~p joined ~p ~p~n", [self(), Node, NextNode]),
            {reply, ok, State#state{next = NextNode}}
    end.
% lookup a key in the dht and return the value to the sender
handle_cast({lookup, Key, From}, State) ->
    case is_between_buckets(Key, State#state.id, get_next_id(State)) of
        true ->
            io:format("found ~p in ~p~n", [Key, self()]),
            From ! {lookup_for, Key, dict:find(Key, State#state.tbl)};
        false ->
            gen_server:cast(State#state.next, {lookup, Key, From})
    end,
    {noreply, State};
% find the bucket position when there's only one node in the ring
handle_cast({find_bucket_position, _NewID, From}, State) when self() == State#state.next ->
    From ! {target_pair, self(), State#state.next},
    {noreply, State};
% find the best position for NewID
handle_cast({find_bucket_position, NewID, From}, State) ->
    case is_between_buckets(NewID, State#state.id, get_next_id(State)) of
        true ->
            From ! {target_pair, self(), State#state.next};
        false ->
            gen_server:cast(State#state.next, {find_bucket_position, NewID, From})
    end,
    {noreply, State};
% insert a key, value pair in to the dht
handle_cast({insert, Key, Val}, State) ->
    case is_between_buckets(Key, State#state.id, get_next_id(State)) of
        true ->
            io:format("inserting ~p into ~p~n", [Val, self()]),
            {noreply, State#state{tbl = dict:store(Key, Val, State#state.tbl)}};
        false ->
            gen_server:cast(State#state.next, {insert, Key, Val}),
            {noreply, State}
    end;
% drop a message when N is 0
handle_cast({forward, N, M}, State) when N < 1 ->
    io:format("~p Dropping ~p~n", [State#state.id, M]),
    {noreply, State};
% forward a message to the next node (repeat N times)
handle_cast({forward, N, M}, State) ->
    io:format("~p (~p keys in bucket) Forwarding ~p to ~p~n", [self(), dict:size(State#state.tbl), M, State#state.next]),
    gen_server:cast(State#state.next, {forward, N - 1, M}),
    {noreply, State};
% print every other message received
handle_cast(R, State) ->
    io:format("Got ~p~n", [R]),
    {noreply, State}.
