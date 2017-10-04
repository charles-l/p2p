-module(lookup).
-compile([export_all]).
%-export([lookup/2]).

%lookup(start, key) ->
%    node = find_node(start, key).

serve() ->
    receive
        R ->
            io:format("Got ~s~n", [R]),
            serve()
    end.

ping(Id, Msg) ->
    Id ! Msg.

run() ->
    Pid = spawn(?MODULE, serve, []),
    {_, [{IpTuple,_,_}|_]} = inet:getif(),
    io:format("~p~p", [IpTuple, self()]),
    Id = crypto:hash(md4, lists:flatten(io_lib:format("~p~p", [IpTuple, self()]))),
    Name = lists:concat(lists:map(fun(X) -> integer_to_list(X, 16) end, binary:bin_to_list(Id))),
    io:format("Server name ~s~n", [Name]),

    ping(Pid, request1),
    ping(Pid, request2),
    ok.
