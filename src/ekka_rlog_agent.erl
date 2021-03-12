%%--------------------------------------------------------------------
%% Copyright (c) 2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% @doc This module implements a gen_statem which pushes rlogs to
%% a remote node.
%%
%% The state machine consists of 3 states:
%% `catchup', `switchover', `normal', which are explained in detail below:
%%
%%
%% All sends are done as `gen_rpc' calls to the replicant node.

-module(ekka_rlog_agent).

-behaviour(gen_statem).

%% API:
-export([start_link/3, stop/1]).

%% gen_statem callbacks:
-export([init/1, terminate/3, code_change/4, callback_mode/0, handle_event/4]).

-include_lib("snabbkaffe/include/snabbkaffe.hrl").

%% Concurrent transactions (rlog entries) may each other and result in
%% disorder. e.g. transaction A having timestamp 1 is logged *after*
%% transaction B with timestamp 2.
-define(CHECKPOINT_MARGIN_SECONDS, 60).

%% Define macros for each state to prevent typos:
-define(catchup, catchup).
-define(switchover, switchover).
-define(normal, normal).

-type state() :: ?catchup | ?switchover | ?normal.

-record(d,
        {
        }).

-type data() :: #d{}.

%%--------------------------------------------------------------------
%% API functions
%%--------------------------------------------------------------------

start_link(Shard, Subscriber, ReplaySince) ->
    gen_statem:start_link(?MODULE, {Shard, Subscriber, ReplaySince}, []).

stop(Pid) ->
    try
        gen_statem:call(Pid, stop, infinity)
    catch
        exit : {noproc, _} ->
            %% race condition, the process exited
            %% before or during this call
            ok
    end.

%%--------------------------------------------------------------------
%% gen_statem callbacks
%%--------------------------------------------------------------------

callback_mode() -> [handle_event_function, state_enter].

-spec init({ekka_rlog:shard(), ekka_rlog_lib:subscriber(), ekka_rlog_lib:txid()}) -> {ok, state(), data()}.
init({Shard, Subscriber, ReplaySince}) ->
    logger:update_process_metadata(#{ domain     => [ekka, rlog, agent]
                                    , shard      => Shard
                                    , subscriber => Subscriber
                                    }),
    {ok, ?normal, #d{}}.

-spec handle_event(gen_statem:event_type(), _EventContent, state(), data()) ->
          gen_statem:event_handler_result(state()).
%% Common actions:
handle_event({call, From}, stop, State, Data) ->
    handle_stop(State, Data),
    {stop_and_reply, normal, {reply, From, ok}};
handle_event(enter, OldState, State, Data) ->
    handle_state_trans(OldState, State, Data),
    keep_state_and_data;
handle_event(EventType, Event, State, Data) ->
    handle_unknown(EventType, Event, State, Data),
    keep_state_and_data.

code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

terminate(_Reason, _State, _Data) ->
    ok.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

handle_stop(State, Data) ->
    ?tp(rlog_agent_stop,
        #{ state => State
         , data => Data
         }).

handle_unknown(EventType, Event, State, Data) ->
    ?tp(warning, "rlog agent received unknown event",
        #{ event_type => EventType
         , event => Event
         , state => State
         , data => Data
         }).

handle_state_trans(OldState, State, _Data) ->
    ?tp(rlog_agent_state_change,
        #{ from => OldState
         , to => State
         }).