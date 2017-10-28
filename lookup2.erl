% references:
%   + https://learnxinyminutes.com/docs/erlang/
%   + http://erlang-tutorials.colefichter.ca/dht1
%   + http://www.linuxjournal.com/article/6797
%   + http://erlang.org/doc/design_principles/gen_server_concepts.html
%   + http://learnyousomeerlang.com/clients-and-servers
%
% lessons learned:
%   + distributed applications are *hard*
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
          id = nil
}).

hashstr(S) -> % hash a string and return a string
    <<H:160/big-unsigned-integer>> = crypto:hash(sha, S),
    lists:flatten(io_lib:format("~40.16.0b", [H])).

id() -> % convert IP address + pid into a hashed value
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    hashstr(lists:flatten(io_lib:format("~p~p", [IpTuple, self()]))).

spawn_ring(N) ->
    {ok, Head} = gen_server:start_link(?MODULE, #state{}, []),
    gen_server:call(Head, {set_next, Head}),
    lists:map(
      fun({_, X}) -> gen_server:call(X, {join_ring, Head}) end,
      [gen_server:start_link(?MODULE, #state{}, []) || _ <- lists:seq(1, N)]),
    Head.

init(S) -> {ok, S#state{id=id()}}.

handle_call({id}, _From, State) ->
    {reply, State#state.id, State};
handle_call({next}, _From, State) ->
    {reply, State#state.next, State};
handle_call({set_next, N}, _From, State) ->
    {reply, ok, State#state{next = N}};
handle_call({join_ring, Head}, _From, State) ->
    io:format("~p Attempting to join~n", [self()]),
    gen_server:cast(Head, {find_bucket_position, State#state.id, self()}),
    {Node, NextNode} = receive
                           {target_pair, N, NN} -> {N, NN}
                       after ?TIMEOUT ->
                                 erlang:error(join_timeout)
                       end,
    gen_server:call(Node, {set_next, self()}),
    io:format("~p joined ~p ~p~n", [self(), Node, NextNode]),
    {reply, ok, State#state{next = NextNode}}.

handle_cast({find_bucket_position, _NewID, From}, State) when self() == State#state.next ->
    io:format("== Base ==~n"),
    From ! {target_pair, self(), State#state.next},
    {noreply, State};
handle_cast({find_bucket_position, NewID, From}, State) ->
    io:format("== Next ==~n"),
    NextID = gen_server:call(State#state.next, {id}),
    io:format("~p ~p ~p~n", [State#state.id, NewID, NextID]),
    IsAtTail = State#state.id > NextID,
    if
        (NewID > State#state.id andalso (NewID < NextID)) orelse
        (IsAtTail andalso (NewID < NextID) orelse (NewID > State#state.id)) ->
            From ! {target_pair, self(), State#state.next};
        true ->
            gen_server:cast(State#state.next, {find_bucket_position, NewID, From})
    end,
    {noreply, State};
handle_cast({forward, N, M}, State) when N < 1 ->
    io:format("~p Dropping ~p~n", [self(), M]),
    {noreply, State};
handle_cast({forward, N, M}, State) ->
    io:format("~p Forwarding ~p to ~p~n", [self(), M, State#state.next]),
    gen_server:cast(State#state.next, {forward, N - 1, M}),
    {noreply, State};
handle_cast(R, State) ->
    io:format("Got ~p~n", [R]),
    {noreply, State}.
