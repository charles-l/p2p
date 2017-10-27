-module(lookup2).
-compile([export_all]).

hashstr(S) -> % hash a string and return a string
    <<H:160/big-unsigned-integer>> = crypto:hash(sha, S),
    lists:flatten(io_lib:format("~40.16.0b", [H])).

id() -> % convert IP address + pid into a hashed value
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    hashstr(lists:flatten(io_lib:format("~p~p", [IpTuple, self()]))).

await_response() ->
    receive
        R -> R
    after 1000 -> erlang:error(await_fail)
    end.

id_from_pid(Pid) ->
    Pid ! {id, self()},
    {_, P, ID} = await_response(),
    {P, ID}.

next_id_from_pid(Pid) ->
    Pid ! {forward, 1, {id, self()}},
    {_, P, ID} = await_response(),
    {P, ID}.

serve(Next) ->
    receive
        {set_next, N} ->
            serve(N);
        {join_ring, Head} ->
            MyID = id(),
            {HeadPID, HeadID} = id_from_pid(Head),
            {NextPID, NextID} = next_id_from_pid(Head),
            if
                (MyID == NextID) -> erlang:error(server_id_collision);
                ((HeadID == NextID) orelse
                    (MyID > HeadID andalso MyID < NextID) orelse
                    (HeadID > NextID)) -> % or end of loop
                    HeadPID ! {set_next, self()},
                    serve(NextPID);
                % else
                true ->
                    {join_ring, NextID}
            end;
        {id, From} ->
            From ! {id_response, self(), id()},
            serve(Next);
        {forward, N, M} when N < 1 ->
            io:format("~p dropping ~p~n", [self(), M]),
            self() ! M,
            serve(Next);
        {forward, N, M} -> % forward msg to next node
            io:format("~p (~p) ~p forwarding ~p~n", [self(), id(), N, M]),
            Next ! {forward, N - 1, M},
            serve(Next);
        R -> io:format("Got ~p~n", [R]),
             serve(Next)
    end.

spawn_initial() ->
    Node = spawn(?MODULE, serve, [nil]),
    Node ! {set_next, Node}, % loop back on itself
    Node.

spawn_to_ring(R) ->
    New = spawn(?MODULE, serve, [nil]),
    New ! {join_ring, R},
    New.

start() ->
    Ring = spawn_initial(),
    [(fun () -> spawn_to_ring(Ring), timer:sleep(3000) end)() || _ <- lists:seq(1, 10)],
    timer:sleep(1000),
    Ring ! {forward, 9, "PING"},
    ok.

