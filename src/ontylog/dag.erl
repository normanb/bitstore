%%%-------------------------------------------------------------------
%%% File    : dag.erl
%%% Author  : Robert Dionne
%%%
%%% This file is part of Bitstore.
%%%
%%% Bitstore is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% Bitstore is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with Bitstore.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%% Created :  05 Dec 2009 by Robert Dionne <dionne@dionne-associates.com>
%%%
%%% bitstore, Copyright (C) 2009-2010   Dionne Associates, LLC.
%%%-------------------------------------------------------------------
-module(dag).
-author('dionne@dionne-associates.com').

%% API
-export([build_dag/1,
        dag_node/2]).

-import(triple_store, [all_triples/1]).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: 
%% Description:
%%--------------------------------------------------------------------
dag_node(Id, Dict) ->
    receive
        %% add labeled edge to another process
        {add, ArrowId, TargetPid} ->
            NewDict = 
                case dict:find(ArrowId,Dict) of
                    {ok, TargetList} ->
                        dict:store(ArrowId,[TargetPid] ++ TargetList,Dict);
                    error -> dict:store(ArrowId,[TargetPid],Dict)
                end,
            dag_node(Id, NewDict);
        %% send the id of this node to another process
        {name, Pid} -> Pid ! Id,
                  dag_node(Id,Dict);
        %% is node connected to another through a specific labelled
        %% edge
        {can_reach, ArrowId, TargetPid, Pid} ->
            case dict:find(ArrowId,Dict) of
                {ok, AdjNodes} ->
                    case lists:member(TargetPid,AdjNodes) of
                        true -> 
                            Pid ! true;
                        false -> 
                            case lists:any(fun(Node) ->
                                                   Node ! {can_reach,
                                                           ArrowId, TargetPid,
                                                           self()},
                                                   receive true -> true;
                                                           false -> false
                                                   end
                                           end, AdjNodes) of
                                true -> Pid ! true;
                                false -> Pid ! false
                            end
                    end;
                error -> Pid ! false
            end,                                                  
            dag_node(Id, Dict)
    end.

%% from a named mnesia table construct a dag as 
%% a collection of processes, one for each node,
%% each containing a dictionary mapping labelled arrows
%% to lists of target nodes 
build_dag(Table) ->
    Nodes = dict:new(),
    lists:foldl(fun({Source,Arrow,Target}, Acc) ->
                      {SourcePid, NewAcc1} = find_or_create_pid(Source,Acc),
                      {TargetPid, NewAcc2} = find_or_create_pid(Target,NewAcc1),
                      SourcePid ! {add, Arrow, TargetPid},
                      io:format("size of nodes is ~p ~n",[dict:size(NewAcc2)]),
                      NewAcc2
              end, Nodes, all_triples(Table)).
                      

%%====================================================================
%% Internal functions
%%====================================================================
find_or_create_pid(Id,Nodes) ->
    case dict:find(Id,Nodes) of
        {ok, Pid} ->
            io:format("found id ~n",[]),
            {Pid, Nodes};
        error ->
            io:format("spawning node for ~p ~n",[Id]),
            Pid = spawn(?MODULE, dag_node, [Id, dict:new()]),
            NewNodes = dict:store(Id, Pid, Nodes),
            {Pid, NewNodes}            
    end.
    
