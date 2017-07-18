%%%===================================================================
%%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%===================================================================

-module(ekka_cluster_strategy).

-ifdef(use_specs).

-type(options() :: list(proplists:property())).

-callback(nodelist(Options :: options()) -> list(node())}).

-callback(register(Options :: options()) -> ok | ignore).

-callback(unregister(Options :: options()) -> ok).

-else.

-export([behaviour_info/1]).

behaviour_info(callbacks) ->
    [{nodelist, 1}, {register, 1}, {unregister, 1}];
behaviour_info(_Other) ->
    undefined.

-endif.

