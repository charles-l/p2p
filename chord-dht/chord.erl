% references:
%   https://en.wikipedia.org/wiki/Chord_(peer-to-peer)
-module(chord).
-export([spawn_ring/1, forward/2, lookup/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-behavior(gen_server).
-define(M, 10).
-define(MAX, round(math:pow(2, ?M))).
-define(TICKINTERVAL, 2000).
-define(TIMEOUT, 10000).

-record(idpair, {
         id = nil,
         pid = nil
         }).

-record(state, {
          id = nil, % the nodes id
          prev = nil, % predecessor id/pid
          tbl = nil, % the server's local hashtable
          finger = []
}).

setnth(L, I, N) -> % set the nth value in a list L
    lists:sublist(L,I - 1) ++ [N] ++ lists:nthtail(I,L).

successor(State) -> % get the first element in the finger table (the successor).
    [S | _] = State#state.finger,
    S.

set_successor(State, Succ) -> % set the first element in the finger table
    [_ | R] = State#state.finger,
    State#state{finger = [Succ | R]}.

selfpair(State) -> % generate an idpair from a nodes State
    #idpair{id = State#state.id, pid = self()}.

% formats I has a hash string
formathash(I) ->
    lists:flatten(io_lib:format("~40.16.0b", [I])).

% generate a hash string for S
hashstr(S) -> % hash a string and return a string of the hash
    <<H:160/big-unsigned-integer>> = crypto:hash(sha, S),
    formathash(H rem ?MAX).

% checks if B is in range (A, C).
between(A, _, A) -> % edge case: one node in the ring pointing to itself
    true;
between(A, B, C) when A < C -> % range check
    A < B andalso B < C;
% edge case: when A and C are swapped, check the outside of the
% range (i.e. the rest of the circle besides the range (A, C).
between(A, B, C) ->
    A < B orelse B < C.

% between check, right inclusive, i.e. is B in (A, C].
between_rin(A, B, C) ->
    C == B orelse between(A, B, C).

genid() -> % convert IP address + pid into a hashed value (so each server gets a unique id)
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    hashstr(lists:flatten(io_lib:format("~p~p", [IpTuple, self()]))).

forward(Node, Message) -> % forward a message to the next node
    gen_server:cast(Node, {forward, Message, 15}).

lookup(Node, Key) ->
    K = hashstr(Key),
    gen_server:cast(Node, {find_successor, K, K, self()}),
    receive
        {successor_for, K, V} -> V
    after
        ?TIMEOUT -> {error, timeout}
    end.

% create a node in the dht
create() ->
    {ok, N} = gen_server:start_link(?MODULE, #state{}, []),
    N.

% create a node for the dht and have it join starting at Head
create_and_join(Head) ->
    N = create(),
    gen_server:call(N, {join, Head}),
    N.

% spawn the initial ring
spawn_ring(N) ->
    H = create(),
    [H | [create_and_join(H) || _ <- lists:seq(1, N)]].

% find the closest node to ID that's directly before it
closest_preceding_from_self(State, ID) ->
    closest_preceding_node(selfpair(State), lists:reverse(State#state.finger), ID).

% idpair -> [idpair] -> id -> idpair
closest_preceding_node(Node, [], _) ->
    Node;
closest_preceding_node(Node, [H|T], ID) ->
    case (H /= nil) andalso between(Node#idpair.id, H#idpair.id, ID) of
        true -> H;
        _ -> closest_preceding_node(Node, T, ID)
    end.

% init function for gen_server behavior
init(S) ->
    timer:send_interval(?TICKINTERVAL, tick),
    ID = genid(),
    {ok, S#state{id=ID, tbl=dict:new(), finger=[#idpair{id = ID, pid = self()} | [nil || _ <- lists:seq(2, ?M)]]}}.

% terminate function for gen_server behavior
terminate(_, _) -> ok.

% update the finger table (called every TICKINTERVAL)
fix_fingers(State) ->
    I = rand:uniform(?M),
    IntID = list_to_integer(State#state.id, 16),
    FingerID = formathash((IntID + round(math:pow(2, I - 1))) rem ?MAX),
    Next = successor(State),
    gen_server:cast(Next#idpair.pid, {find_successor, I, FingerID, self()}),
    ok.

% join a ring
handle_call({join, H}, _From, State) ->
    gen_server:cast(H, {find_successor, 1, State#state.id, self()}),
    {reply, ok, State}.

% update Ith successor to be N in the finger table
handle_info({successor_for, I, N}, State) ->
    {noreply, State#state{finger = setnth(State#state.finger, I, N)}};

% tick handler (stabilize and fix fingers).
handle_info(tick, State) ->
    Next = successor(State),
    if
        Next /= nil -> gen_server:cast(Next#idpair.pid, {prev, self()})
    end,
    fix_fingers(State),
    {noreply, State};

% generic message
handle_info(M, State) ->
    io:format("~p Unknown message ~p~n", [self(), M]),
    {noreply, State}.

% stabilize this node, (given X = successors predecessor)
handle_cast({stabilize, X}, State) ->
    Next = successor(State),
    case X /= nil andalso between(State#state.id, X#idpair.id, Next#idpair.id) of
        true ->
            {noreply, set_successor(State, X)};
        _ ->
            gen_server:cast(Next#idpair.pid, {notify, selfpair(State)}),
            {noreply, State}
    end;
% tell the node that requested this nodes predecessor to stabilize
handle_cast({prev, From}, State) ->
    gen_server:cast(From, {stabilize, State#state.prev}),
    {noreply, State};

% find successor of ID
handle_cast({find_successor, I, ID, From}, State) ->
    Next = successor(State),
    case between_rin(State#state.id, ID, Next#idpair.id) of
        true ->
            From ! {successor_for, I, Next};
        _ ->
            N = closest_preceding_from_self(State, ID),
            gen_server:cast(N#idpair.pid, {find_successor, I, ID, From})
    end,
    {noreply, State};

% P thinks it might be our predecessor
handle_cast({notify, P}, State) ->
    % P needs to be an idpair
    case (State#state.prev == nil) orelse
         between(State#state.prev#idpair.id, P#idpair.id, State#state.id) of
        true ->
            {noreply, State#state{prev = P}};
        _ ->
            {noreply, State}
    end;
handle_cast({forward, Msg, N}, State) when N == 0 ->
    io:format("~p Dropping ~p~n", [self(), Msg]),
    {noreply, State};
% forward a message to the direct predecessor
handle_cast({forward, Msg, N}, State) ->
    Next = successor(State),
    io:format("~p Forwarding ~p to ~p~n", [self(), Msg, Next]),
    gen_server:cast(Next#idpair.pid, {forward, Msg, N - 1}),
    {noreply, State}.
