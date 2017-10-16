-module(lookup).
-compile([export_all]).

-define(KEYLEN, 30).

% largest possible node ID is 2^KEYLEN
-define(MAXKEY, math:pow(2, ?KEYLEN)).

dist(A, B) ->
    if
        A == B -> 0;
        A < B -> B - A;
        true -> ?MAXKEY + (B - A)
    end.

-record(node, {serverid, successor_pid, hashtbl}).

servername(Pid) ->
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    Id = crypto:hash(md4, lists:flatten(io_lib:format("~p~p", [IpTuple, Pid]))),
    lists:concat(lists:map(fun(X) -> integer_to_list(X, 16) end, binary:bin_to_list(Id))).

make_node(Succ) ->
    #node{serverid=servername(self()), successor_pid=Succ, hashtbl=dict:new()}.

serve(ThisNode) ->
    receive
        {id, P} ->
            P ! ThisNode#node.serverid,
            serve(ThisNode);
        {get_successor, P} ->
            P ! ThisNode#node.successor_pid,
            serve(ThisNode);
        {set_successor, S} ->
            io:format("Changing successor from ~p to ~p~n", [ThisNode#node.successor_pid, S]),
            serve(ThisNode#node{successor_pid=S});
        {insert, K, V} ->
            io:format("adding ~s -> ~s~n", [K, V]),
            serve(dict:store(K, V, ThisNode#node.hashtbl));
        {lookup, K, D} ->
            D ! dict:find(K, ThisNode#node.hashtbl),
            % TODO: send something back
            serve(ThisNode);
        R ->
            io:format("Got ~s~n", [R]),
            serve(ThisNode)
    end.

run() ->
    Pid = spawn(?MODULE, serve, [make_node(nil)]),
    Pid1 = spawn(?MODULE, serve, [make_node(Pid)]),
    Pid ! {id, self()},
    receive
        K -> io:format("Id of child ~s~n", [K])
    end,

    Pid1 ! {set_successor, Pid},
    Pid ! {set_successor, Pid1},
    Pid ! request1,
    Pid ! {insert, "HI", "Yo"},
    ok.
