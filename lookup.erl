-module(lookup).
-compile([export_all]).
%-export([lookup/2]).

%lookup(start, key) ->
%    node = find_node(start, key).

servername(Pid) ->
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    Id = crypto:hash(md4, lists:flatten(io_lib:format("~p~p", [IpTuple, Pid]))),
    lists:concat(lists:map(fun(X) -> integer_to_list(X, 16) end, binary:bin_to_list(Id))).

serve(Suc) ->
    receive
        {successor, S} ->
            io:format("Changing successor from ~s to ~s~n", [Suc, S]),
            serve(S);
        R ->
            io:format("Got ~s (successor ~s)~n", [R, Suc]),
            serve(Suc)
    end.

run() ->
    io:format("Server name ~s~n", [servername(self())]),
    Pid = spawn(?MODULE, serve, ["0"]),
    Pid1 = spawn(?MODULE, serve, [servername(Pid)]),
    io:format("Server name of child ~s~n", [servername(Pid)]),

    Pid1 ! {successor, servername(Pid)},
    Pid ! {successor, servername(Pid1)},
    Pid ! request1,
    ok.
