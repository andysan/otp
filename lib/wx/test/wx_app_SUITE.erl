%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2010. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%%
%%----------------------------------------------------------------------
%% Purpose: Verify the application specifics of the Wx application
%%----------------------------------------------------------------------
-module(wx_app_SUITE).

-compile(export_all).

-include("wx_test_lib.hrl").


t()     -> wx_test_lib:t(?MODULE).
t(Case) -> wx_test_lib:t({?MODULE, Case}).

%% Test server callbacks
init_per_testcase(Case, Config0) ->
    Config1 = wx_test_lib:init_per_testcase(Case, Config0),
    case is_app(wx) of
	{ok, AppFile} ->
	    %% io:format("AppFile: ~n~p~n", [AppFile]),
	    [{app_file, AppFile} | Config1];
	{error, Reason} ->
	    fail(Reason)
    end.

end_per_testcase(Func,Config) ->
    wx_test_lib:end_per_testcase(Func, Config).

fin_per_testcase(Case, Config) ->
    wx_test_lib:end_per_testcase(Case, Config).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

all() ->
    all(suite).

all(suite) ->
    [
     fields,
     modules,
     exportall,
     app_depend,
     undef_funcs
    ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

is_app(App) ->
    LibDir = code:lib_dir(App),
    File = filename:join([LibDir, "ebin", atom_to_list(App) ++ ".app"]),
    case file:consult(File) of
	{ok, [{application, App, AppFile}]} ->
	    {ok, AppFile};
	Error ->
	    {error, {invalid_format, Error}}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fields(suite) ->
    [];
fields(doc) ->
    [];
fields(Config) when is_list(Config) ->
    AppFile = key1search(app_file, Config),
    Fields = [vsn, description, modules, registered, applications],
    case check_fields(Fields, AppFile, []) of
	[] ->
	    ok;
	Missing ->
	    fail({missing_fields, Missing})
    end.

check_fields([], _AppFile, Missing) ->
    Missing;
check_fields([Field|Fields], AppFile, Missing) ->
    check_fields(Fields, AppFile, check_field(Field, AppFile, Missing)).

check_field(Name, AppFile, Missing) ->
    io:format("checking field: ~p~n", [Name]),
    case lists:keymember(Name, 1, AppFile) of
	true ->
	    Missing;
	false ->
	    [Name|Missing]
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

modules(suite) ->
    [];
modules(doc) ->
    [];
modules(Config) when is_list(Config) ->
    AppFile  = key1search(app_file, Config),
    Mods     = key1search(modules, AppFile),
    EbinList = get_ebin_mods(wx),
    case missing_modules(Mods, EbinList, []) of
	[] ->
	    ok;
	Missing ->
	    throw({error, {missing_modules, Missing}})
    end,
    case extra_modules(Mods, EbinList, []) of
	[] ->
	    ok;
	Extra ->
	    throw({error, {extra_modules, Extra}})
    end,
    {ok, Mods}.

get_ebin_mods(App) ->
    LibDir  = code:lib_dir(App),
    EbinDir = filename:join([LibDir,"ebin"]),
    {ok, Files0} = file:list_dir(EbinDir),
    Files1 = [lists:reverse(File) || File <- Files0],
    [list_to_atom(lists:reverse(Name)) || [$m,$a,$e,$b,$.|Name] <- Files1].

missing_modules([], _Ebins, Missing) ->
    Missing;
missing_modules([Mod|Mods], Ebins, Missing) ->
    case lists:member(Mod, Ebins) of
	true ->
	    missing_modules(Mods, Ebins, Missing);
	false ->
	    io:format("missing module: ~p~n", [Mod]),
	    missing_modules(Mods, Ebins, [Mod|Missing])
    end.


extra_modules(_Mods, [], Extra) ->
    Extra;
extra_modules(Mods, [Mod|Ebins], Extra) ->
    case lists:member(Mod, Mods) of
	true ->
	    extra_modules(Mods, Ebins, Extra);
	false ->
	    io:format("supefluous module: ~p~n", [Mod]),
	    extra_modules(Mods, Ebins, [Mod|Extra])
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

exportall(suite) ->
    [];
exportall(doc) ->
    [];
exportall(Config) when is_list(Config) ->
    AppFile = key1search(app_file, Config),
    Mods    = key1search(modules, AppFile),
    check_export_all(Mods).


check_export_all([]) ->
    ok;
check_export_all([Mod|Mods]) ->
    case (catch apply(Mod, module_info, [compile])) of
	{'EXIT', {undef, _}} ->
	    check_export_all(Mods);
	O ->
            case lists:keysearch(options, 1, O) of
                false ->
                    check_export_all(Mods);
                {value, {options, List}} ->
                    case lists:member(export_all, List) of
                        true ->
			    throw({error, {export_all, Mod}});
			false ->
			    check_export_all(Mods)
                    end
            end
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

app_depend(suite) ->
    [];
app_depend(doc) ->
    [];
app_depend(Config) when is_list(Config) ->
    AppFile = key1search(app_file, Config),
    Apps    = key1search(applications, AppFile),
    check_apps(Apps).

check_apps([]) ->
    ok;
check_apps([App|Apps]) ->
    case is_app(App) of
	{ok, _} ->
	    check_apps(Apps);
	Error ->
	    throw({error, {missing_app, {App, Error}}})
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

undef_funcs(suite) ->
    [];
undef_funcs(doc) ->
    [];
undef_funcs(Config) when is_list(Config) ->
    catch test_server:timetrap(timer:minutes(10)),
    App            = wx,
    AppFile        = key1search(app_file, Config),
    Mods           = key1search(modules, AppFile),
    Root           = code:root_dir(),
    LibDir         = code:lib_dir(App),
    EbinDir        = filename:join([LibDir,"ebin"]),
    XRefTestName   = undef_funcs_make_name(App, xref_test_name),
    {ok, XRef}     = xref:start(XRefTestName),
    ok             = xref:set_default(XRef,
                                      [{verbose,false},{warnings,false}]),
    XRefName       = undef_funcs_make_name(App, xref_name),
    {ok, XRefName} = xref:add_release(XRef, Root, {name,XRefName}),
    {ok, App}      = xref:replace_application(XRef, App, EbinDir),
    {ok, Undefs}   = xref:analyze(XRef, undefined_function_calls),
    xref:stop(XRef),
    analyze_undefined_function_calls(Undefs, Mods, []).

analyze_undefined_function_calls([], _, []) ->
    ok;
analyze_undefined_function_calls([], _, AppUndefs) ->
    exit({suite_failed, {undefined_function_calls, AppUndefs}});
analyze_undefined_function_calls([{{Mod, _F, _A}, _C} = AppUndef|Undefs],
                                 AppModules, AppUndefs) ->
    %% Check that this module is ours
    case lists:member(Mod,AppModules) of
        true ->
            {Calling,Called} = AppUndef,
            {Mod1,Func1,Ar1} = Calling,
            {Mod2,Func2,Ar2} = Called,
            io:format("undefined function call: "
                      "~n   ~w:~w/~w calls ~w:~w/~w~n",
                      [Mod1,Func1,Ar1,Mod2,Func2,Ar2]),
            analyze_undefined_function_calls(Undefs, AppModules,
                                             [AppUndef|AppUndefs]);
        false ->
            io:format("dropping ~p~n", [Mod]),
            analyze_undefined_function_calls(Undefs, AppModules, AppUndefs)
    end.

%% This function is used simply to avoid cut-and-paste errors later...
undef_funcs_make_name(App, PostFix) ->
    list_to_atom(atom_to_list(App) ++ "_" ++ atom_to_list(PostFix)).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fail(Reason) ->
    exit({suite_failed, Reason}).

key1search(Key, L) ->
    case lists:keysearch(Key, 1, L) of
	false ->
	    fail({not_found, Key, L});
	{value, {Key, Value}} ->
	    Value
    end.
