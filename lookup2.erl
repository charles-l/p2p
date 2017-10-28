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

-module(lookup2).
-compile([export_all]).
-behavior(gen_server).
-define(TIMEOUT, 3000).

-record(state, {
          next = nil,
          id = nil,
          tbl = nil
}).

hashstr(S) -> % hash a string and return a string
    <<H:160/big-unsigned-integer>> = crypto:hash(sha, S),
    lists:flatten(io_lib:format("~40.16.0b", [H])).

genid() -> % convert IP address + pid into a hashed value
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    hashstr(lists:flatten(io_lib:format("~p~p", [IpTuple, self()]))).

insert(Node, Key, Val) ->
    gen_server:cast(Node, {insert, hashstr(Key), Val}).

lookup(Node, Key) ->
    K = hashstr(Key),
    gen_server:cast(Node, {lookup, K, self()}),
    Val = receive
              {lookup_for, K, R} -> R
          after ?TIMEOUT -> erlang:error(lookup_timeout)
          end,
    Val.

spawn_ring(N) ->
    {ok, Head} = gen_server:start_link(?MODULE, #state{}, []),
    gen_server:call(Head, {set_next, Head}),
    lists:map(
      fun({_, X}) -> gen_server:call(X, {join_ring, Head}) end,
      [gen_server:start_link(?MODULE, #state{}, []) || _ <- lists:seq(1, N)]),
    Head.

init(S) -> {ok, S#state{id=genid(), tbl=dict:new()}}.

is_between_buckets(NewID, NodeID, NextID) ->
    IsAtTail = NodeID > NextID,
    if
        ((NewID > NodeID) andalso (NewID < NextID)) orelse
        (IsAtTail andalso ((NewID < NextID) orelse (NewID > NodeID))) ->
            true;
        true ->
            false
    end.

handle_call({id}, _From, State) ->
    {reply, State#state.id, State};
handle_call({next}, _From, State) ->
    {reply, State#state.next, State};
handle_call({set_next, N}, _From, State) ->
    {reply, ok, State#state{next = N}};
handle_call({join_ring, Head}, _From, State) ->
    gen_server:cast(Head, {find_bucket_position, State#state.id, self()}),
    {Node, NextNode} = receive
                           {target_pair, N, NN} -> {N, NN}
                       after ?TIMEOUT ->
                                 erlang:error(join_timeout)
                       end,
    gen_server:call(Node, {set_next, self()}),
    io:format("~p joined ~p ~p~n", [self(), Node, NextNode]),
    {reply, ok, State#state{next = NextNode}}.

handle_cast({insert, Key, Val}, State) ->
    NextID = gen_server:call(State#state.next, {id}),
    case is_between_buckets(Key, State#state.id, NextID) of
        true ->
            {noreply, State#state{tbl = dict:store(Key, Val, State#state.tbl)}};
        false ->
            gen_server:cast(State#state.next, {insert, Key, Val}),
            {noreply, State}
    end;
handle_cast({lookup, Key, From}, State) ->
    NextID = gen_server:call(State#state.next, {id}),
    case is_between_buckets(Key, State#state.id, NextID) of
        true ->
            From ! {lookup_for, Key, dict:find(Key, State#state.tbl)};
        false ->
            gen_server:cast(State#state.next, {lookup, Key, From})
    end,
    {noreply, State};
handle_cast({find_bucket_position, _NewID, From}, State) when self() == State#state.next ->
    From ! {target_pair, self(), State#state.next},
    {noreply, State};
handle_cast({find_bucket_position, NewID, From}, State) ->
    NextID = gen_server:call(State#state.next, {id}),
    case is_between_buckets(NewID, State#state.id, NextID) of
        true ->
            From ! {target_pair, self(), State#state.next};
        false ->
            gen_server:cast(State#state.next, {find_bucket_position, NewID, From})
    end,
    {noreply, State};
handle_cast({forward, N, M}, State) when N < 1 ->
    io:format("~p Dropping ~p~n", [State#state.id, M]),
    {noreply, State};
handle_cast({forward, N, M}, State) ->
    io:format("~p (~p) Forwarding ~p to ~p~n", [self(), dict:size(State#state.tbl), M, State#state.next]),
    gen_server:cast(State#state.next, {forward, N - 1, M}),
    {noreply, State};
handle_cast(R, State) ->
    io:format("Got ~p~n", [R]),
    {noreply, State}.
