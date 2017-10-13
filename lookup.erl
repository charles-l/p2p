-module(lookup).
-compile([export_all]).

closest_node(NodeID, SuccessorID, Key) ->
    MaxKey = math:pow(30, 2),
    if
        NodeID > SuccessorID, (MaxKey - SuccessorID - Key) > (Key - NodeID) -> NodeID;
        NodeID > SuccessorID -> SuccessorID;
        (Key - NodeID) > (SuccessorID - Key) -> SuccessorID;
        true -> NodeID
    end.

get_id_pair(N) ->
    N ! {id, self()},
    CID = receive I -> I end,
    N ! {get_successor_id, self()},
    NID = receive J -> J end,
    {CID, NID}.

find_node(Start, Key) ->
    InnerFind = fun (Current, Next) ->
                        if
                            Current <= Key < Next -> {Current, CurrentNext};
                            Key > Current > Next -> {Current, CurrentNext};
                            true -> InnerFind(Next, NextNext)
                        end,
                        {C, CN} = InnerFind(Start, StartNext),
                        closest_node(C, CN, Key).


servername(Pid) ->
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    Id = crypto:hash(md4, lists:flatten(io_lib:format("~p~p", [IpTuple, Pid]))),
    lists:concat(lists:map(fun(X) -> integer_to_list(X, 16) end, binary:bin_to_list(Id))).

-record(node, {pid, id, suc, tbl}).

serve(Tbl, Suc) ->
    receive
        {id, P} ->
            P ! servername(self()),
            serve(Tbl, Suc);
        {get_successor, P} ->
            P ! Suc,
            serve(Tbl, Suc);
        {set_successor, S} ->
            io:format("Changing successor from ~s to ~s~n", [Suc, S]),
            serve(Tbl, S);
        {forward, M} -> % forward a message to sucessor
            Suc ! M,
            serve(Tbl, Suc);
        {insert, K, V} ->
            io:format("adding ~s -> ~s~n", [K, V]),
            serve(dict:store(K, V, Tbl), Suc);
        {lookup, K, D} ->
            D ! dict:find(K, Tbl),
            % TODO: send something back
            serve(Tbl, Suc);
        R ->
            io:format("Got ~s~n", [R]),
            serve(Tbl, Suc)
    end.

run() ->
    Pid = spawn(?MODULE, serve, [dict:new(), "0"]),
    Pid1 = spawn(?MODULE, serve, [dict:new(), servername(Pid)]),
    Pid ! {id, self()},
    receive
        K -> io:format("Id of child ~s~n", [K])
    end,

    Pid1 ! {successor, Pid},
    Pid ! {successor, Pid1},
    Pid ! request1,
    Pid ! {insert, "HI", "Yo"},
    ok.
