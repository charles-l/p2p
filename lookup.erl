-module(lookup).
-compile([export_all]).

-define(KEYLEN, 30).

% largest possible node ID is 2^KEYLEN
-define(MAXKEY, math:pow(2, ?KEYLEN)).

dist(A, B) ->
    <<X:128>> = A,
    <<Y:128>> = B,
    if
        X == Y -> 0;
        X < Y -> X - Y;
        true -> ?MAXKEY + (X - Y)
    end.

-record(node, {
          server_id, % the hashed id of the server, used for bucket lookup
          successor_pid, % the pid of the next node in the ring
          hashtbl % the hash table for this node
         }).

server_name(Pid) ->
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    crypto:hash(md4, lists:flatten(io_lib:format("~p~p", [IpTuple, Pid]))).

hash_key(K) ->
    crypto:hash(md4, K).

start_node(Succ) ->
    serve(#node{server_id=server_name(self()), successor_pid=Succ, hashtbl=dict:new()}).

get_successor_id(SuccPID) ->
    SuccPID ! {server_id, self()},
    receive
        {id_response, R} -> R
    end.


serve(State) ->
    receive
        {server_id, Return} ->
            Return ! {id_response, State#node.server_id},
            serve(State);
        {set_successor, S} ->
            io:format("Changing successor from ~p to ~p~n", [State#node.successor_pid, S]),
            serve(State#node{successor_pid=S});
        {insert, K, V} ->
            H = hash_key(K),
            io:format("adding ~s (~p) -> ~s~n", [K, H, V]),
            serve(State#node{hashtbl = dict:store(H, V, State#node.hashtbl)});
        {lookup, K, Return} ->
            H = hash_key(K),
            SuccID = get_successor_id(State#node.successor_pid),
            case dist(State#node.server_id, H) < dist(SuccID, H) of
                true -> io:format("DID IT WORK ~w~n", [dict:find(H, State#node.hashtbl)]), Return ! dict:find(H, State#node.hashtbl);
                false -> State#node.successor_pid ! {lookup, H, Return} % forward on to next node in ring
            end,
            serve(State);
        R ->
            io:format("Got ~p~n", [R]),
            serve(State)
    end.


run() ->
    Pid = spawn(?MODULE, start_node, [nil]),
    Pid1 = spawn(?MODULE, start_node, [Pid]),

    Pid1 ! {set_successor, Pid},
    Pid ! {set_successor, Pid1},
    Pid ! request1,
    Pid1 ! {insert, "asdf", "Yo"},
    Pid ! {lookup, "asdf", self()},
    ok.
