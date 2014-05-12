-module(xep_0280_carboncopy_SUITE).

-compile([export_all]).
-include_lib("common_test/include/ct.hrl").
-include_lib("proper/include/proper.hrl").

all() ->
    [{group, properties},{group, essential}].

groups() ->
    [{essential, [discovering_support,
                  enabling_carbons,
                  disabling_carbons,
                  avoiding_carbons,
                  non_enabled_clients_dont_get_sent_carbons,
                  non_enabled_clients_dont_get_received_carbons
                 ]},
    {properties, [run_properties]}].

prop_names() ->
    [p_forward_received_chat_messages,
     p_forward_sent_chat_messages,
     p_normal_routing_to_bare_jid].

init_per_suite(Config) ->
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus:end_per_suite(Config).

init_per_group(_, Config) ->
    escalus:create_users(Config).

end_per_group(_, Config) ->
    escalus:delete_users(Config).

init_per_testcase(CaseName,Config) ->
    escalus:init_per_testcase(CaseName,Config).

end_per_testcase(CaseName,Config) ->
    escalus:end_per_testcase(CaseName,Config).


%%
%%  Properties {group, properties}
%%

run_properties(Config) ->
    Props = proper:conjunction([mk_prop(P, Config) || P <- prop_names()]),
    true = proper:quickcheck(Props, [verbose,long_result, {numtests, 5}]).

mk_prop(PropName, Config) ->
    %% Instantiate a property with a CT config object,
    %% Return a tuple for proper:conjunction to use
    {PropName, apply(?MODULE, PropName, [Config])}.


%%
%%  CT tests {group, essential}
%%

discovering_support(Config) ->
    escalus:story(
      Config, [{alice, 1}],
      fun(Alice) ->
              IqGet = escalus_stanza:disco_info(<<"localhost">>),
              escalus_client:send(Alice, IqGet),
              Result = escalus_client:wait_for_stanza(Alice),
              escalus:assert(is_iq_result, [IqGet], Result),
              escalus:assert(has_feature, [<<"urn:xmpp:carbons:2">>], Result)
      end).

enabling_carbons(Config) ->
    escalus:story(Config, [{alice, 1}], fun carbons_get_enabled/1).

disabling_carbons(Config) ->
    escalus:story(Config, [{alice, 1}],
                  fun(Alice) -> carbons_get_enabled(Alice),
                                carbons_get_disabled(Alice) end).


avoiding_carbons(Config) ->
    escalus:story(
      Config, [{alice, 2}, {bob, 1}],
      fun(Alice1, Alice2, Bob) ->
              carbons_get_enabled([Alice1,Alice2]),
              Msg = escalus_stanza:chat_without_carbon_to(
                      Bob, <<"And pious action">>),
              escalus_client:send(Alice1, Msg),
              escalus:assert(
                is_chat_message, [<<"And pious action">>],
                escalus_client:wait_for_stanza(Bob)),
              escalus_client:wait_for_stanzas(Alice2, 1),
              [] = escalus_client:peek_stanzas(Alice2)
      end).

non_enabled_clients_dont_get_sent_carbons(Config) ->
    escalus:story(
      Config, [{alice, 2}, {bob, 1}],
      fun(Alice1, Alice2, Bob) ->
              Msg = escalus_stanza:chat_to(Bob, <<"And pious action">>),
              escalus_client:send(Alice1, Msg),
              escalus:assert(
                is_chat_message, [<<"And pious action">>],
                escalus_client:wait_for_stanza(Bob)),
              escalus_client:wait_for_stanzas(Alice2, 1),
              [] = escalus_client:peek_stanzas(Alice2)
      end).

non_enabled_clients_dont_get_received_carbons(Config) ->
    escalus:story(
      Config, [{alice, 2}, {bob, 1}],
      fun(Alice1, Alice2, Bob) ->
              Msg = escalus_stanza:chat_to(Alice1, <<"And pious action">>),
              escalus_client:send(Bob, Msg),
              escalus:assert(
                is_chat_message, [<<"And pious action">>],
                escalus_client:wait_for_stanza(Alice1)),
              escalus_client:wait_for_stanzas(Alice2, 1),
              [] = escalus_client:peek_stanzas(Alice2)
      end).


%%
%% Property generators
%% TODO: Consider moving to separate lib (escalus_prop?)
%%

p_forward_received_chat_messages(Config) ->
    ?FORALL({N,Msg}, {no_of_resources(), utterance()},
            true_story(Config, [{alice, 1}, {bob, N}],
                       fun(Users) ->
                               all_bobs_other_resources_get_received_carbons(Users,Msg)
                       end)).

p_forward_sent_chat_messages(Config) ->
    ?FORALL({N,Msg}, {no_of_resources(),utterance()},
            true_story(Config, [{alice, 1}, {bob, N}],
                       fun(Users) ->
                               all_bobs_other_resources_get_sent_carbons(Users,Msg)
                       end)).

p_normal_routing_to_bare_jid(Config) ->
    ?FORALL({N,Msg}, {no_of_resources(),utterance()},
            true_story(Config, [{alice, 1}, {bob, N}],
                       fun(Users) ->
                               all_bobs_resources_get_message_to_bare_jid(Users,Msg)
                       end)).


%%
%% Test scenarios w/assertions
%%

all_bobs_resources_get_message_to_bare_jid([Alice,Bob1|Bobs], Msg) ->
    %% All connected resources receive messages sent
    %% to the user's bare JID without carbon wrappers.

    carbons_get_enabled([Bob1|Bobs]),
    escalus_client:send(
      Alice, escalus_stanza:chat_to(escalus_client:short_jid(Bob1), Msg)),
    GotMsg = fun(BobsResource) ->
                     escalus:assert(
                       is_chat_message,
                       [Msg],
                       escalus_client:wait_for_stanza(BobsResource))
             end,
    lists:foreach(GotMsg, [Bob1|Bobs]).

all_bobs_other_resources_get_received_carbons([Alice,Bob1|Bobs], Msg) ->
    carbons_get_enabled([Bob1|Bobs]),
    escalus_client:send(Alice, escalus_stanza:chat_to(Bob1, Msg)),
    GotForward = fun(BobsResource) ->
                         escalus:assert(
                           is_forwarded_received_message,
                           [escalus_client:full_jid(Alice),
                            escalus_client:full_jid(Bob1),
                            Msg],
                           escalus_client:wait_for_stanza(BobsResource)) end,
    lists:foreach(GotForward, Bobs).

all_bobs_other_resources_get_sent_carbons([Alice,Bob1|Bobs], Msg) ->
    carbons_get_enabled([Bob1|Bobs]),
    escalus_client:send(Bob1, escalus_stanza:chat_to(Alice, Msg)),
    escalus:assert(is_chat_message, [Msg], escalus_client:wait_for_stanza(Alice)),
    GotCarbon = fun(BobsResource) ->
                        escalus:assert(
                          is_forwarded_sent_message,
                          [escalus_client:full_jid(Bob1),
                           escalus_client:full_jid(Alice),
                           Msg],
                          escalus_client:wait_for_stanza(BobsResource)) end,
    lists:foreach(GotCarbon, Bobs).

carbons_get_disabled(ClientOrClients) ->
    carbon_helper:disable_carbons(ClientOrClients).

carbons_get_enabled(ClientOrClients) ->
    carbon_helper:enable_carbons(ClientOrClients).


%%
%% Internal helpers
%%

%% Wrapper around escalus:story. Returns PropEr result.
true_story(Config, UserSpecs, TestFun) ->
    try   escalus:story(Config, UserSpecs, TestFun), true
    catch E -> {error, E}
    end.

%% Number of resources per users
no_of_resources() -> random:uniform(4).

%% A sample chat message
utterance() ->
    proper_types:oneof(
      [<<"Now, fair Hippolyta, our nuptial hour">>,
       <<"Draws on apace; four happy days bring in">>,
       <<"Another moon: but, O, methinks, how slow">>,
       <<"This old moon wanes! she lingers my desires">>,
       <<"Like to a step-dame or a dowager">>,
       <<"Long withering out a young man revenue.">>]).
