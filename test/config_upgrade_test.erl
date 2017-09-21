-module(config_upgrade_test).

-include_lib("eunit/include/eunit.hrl").

config_code_upgrade_test_() ->
    {
        foreach,
        fun setup/0,
        fun teardown/1,
        [
            fun t_migrate_ets_content_after_upgrade/1,
            fun t_code_change_is_called_on_downgrade/1
        ]
    }.

setup() ->
    {ok, EventMgrPid} = gen_event:start_link({local, config_event}),
    {ok, Pid} = config:start_link([]),
    lists:map(fun(Idx) ->
        Key = "key_" ++ integer_to_list(Idx),
        Value = "value_" ++ integer_to_list(Idx),
        config:set("section", Key, Value, false)
    end, lists:seq(1, 50)),
    ?assertEqual(50, ets:info(config, size)),

    ok = meck:expect(twig, log, 3, ok),
    {Pid, EventMgrPid, ets:info(config, size)}.

teardown({Pid, EventMgrPid, _Size}) ->
    unlink(Pid),
    exit(Pid, kill),
    unlink(EventMgrPid),
    exit(EventMgrPid, kill),
    meck:unload(twig).


t_migrate_ets_content_after_upgrade({Pid, _EventMgrPid, Size}) ->
    ?_test(begin
        hot_code_upgrade(Pid, config, 1),
        ?assertEqual(Size, ets:info(config, size)),
        LogArgs = meck:capture(first, twig, log, [notice, '_', '_'], 3),
        ?assertMatch([config, 1], LogArgs),
        ?assert(is_process_alive(Pid)),
        ok
    end).

t_code_change_is_called_on_downgrade({Pid, _EventMgrPid, Size}) ->
    ?_test(begin
        hot_code_upgrade(Pid, config, 1),
        meck:reset(twig),
        hot_code_upgrade(Pid, config, {down, 2}),
        ?assertEqual(Size, ets:info(config, size)),
        LogArgs = meck:capture(first, twig, log, [notice, '_', '_'], 3),
        ?assertMatch([config, {down, 2}], LogArgs),
        ?assert(is_process_alive(Pid)),
        ok
    end).

hot_code_upgrade(Pid, Module, OldVsn) ->
    ok = sys:suspend(Pid),
    ok = sys:change_code(Pid, Module, OldVsn, extra),
    ok = sys:resume(Pid),
    ok.
