% a p2p semi-twitter-ish clone using the chord protocol
% references:
%   https://en.wikipedia.org/wiki/Chord_(peer-to-peer)
-module(twit).
-export([forward/2, timeline/2, create/2, create_and_join/3, post/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-behavior(gen_server).
-define(M, 10).
-define(MAX, round(math:pow(2, ?M))).
-define(TICKINTERVAL, 200).
-define(TIMEOUT, 10000).

-record(idpair, {
         id = nil,
         pid = nil
         }).

-record(state, {
          id = nil, % the nodes id
          username = nil,
          password = "pass",
          prev = nil, % predecessor id/pid
          msgs = [], % user timeline
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

genid(Username) ->
    hashstr(lists:flatten(Username)).

forward(Node, Message) -> % forward a message to the next node
    gen_server:cast(Node, {forward, Message, 15}).

timeline(Node, Username) ->
    K = hashstr(Username),
    gen_server:cast(Node, {timeline_forward, timeline, K, self()}),
    receive
        {timeline_for, K, V} -> {timeline, Username, V}
    after
        ?TIMEOUT -> {error, timeout}
    end.

post(N, Msg, Pass) ->
    gen_server:call(N, {post, Pass, Msg}).

% Intelligently forward to the next node using the finger table
% FoundF : idpair -> void
% ForwardF : idpair -> void
find_successor(State, ID, ForwardF, FoundF) ->
    Next = successor(State),
    case between_rin(State#state.id, ID, Next#idpair.id) of
        true ->
            FoundF(Next);
        _ ->
            N = closest_preceding_from_self(State, ID),
            ForwardF(N)
    end.

% create a node in the dht
create(Username, Pass) ->
    {ok, N} = gen_server:start_link(?MODULE, #state{username=Username, password=Pass}, []),
    N.

% create a node for the dht and have it join starting at Head
create_and_join(Head, Username, Pass) ->
    N = create(Username, Pass),
    gen_server:call(N, {join, Head}),
    N.

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
    if
        S#state.username == nil ->
           throw("Need username to be assigned");
        true -> ok
    end,
    ID = genid(S#state.username),
    {ok, S#state{id=ID, username=S#state.username, finger=[#idpair{id = ID, pid = self()} | [nil || _ <- lists:seq(2, ?M)]]}}.

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
    {reply, ok, State};

% post a new message
handle_call({post, Pass, Msg}, _From, State) ->
    if
        Pass == State#state.password ->
            {reply, ok, State#state{msgs = [{erlang:localtime(), Msg} | State#state.msgs]}};
        true ->
            {reply, unauthenticated, State}
    end.

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
    find_successor(State, ID,
                  fun(NextN) ->
                          gen_server:cast(NextN#idpair.pid, {find_successor, I, ID, From})
                  end,
                  fun(FoundN) ->
                          From ! {successor_for, I, FoundN}
                  end),
    {noreply, State};

% timeline via find_successor
handle_cast({timeline_forward, M, K, From}, State) ->
    find_successor(State, K,
                  fun(NextN) ->
                          gen_server:cast(NextN#idpair.pid, {timeline_forward, M, K, From})
                  end,
                  fun(FoundN) ->
                          gen_server:cast(FoundN#idpair.pid, {M, K, From})
                  end),
    {noreply, State};

handle_cast({timeline, K, From}, State) ->
    From ! {timeline_for, K, State#state.msgs},
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
