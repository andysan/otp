%% -*- erlang-indent-level: 2 -*-
%%-----------------------------------------------------------------------
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2006-2011. All Rights Reserved.
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

-module(dialyzer_cl_parse).

%% Avoid warning for local function error/1 clashing with autoimported BIF.
-compile({no_auto_import,[error/1]}).
-export([start/0]).
-export([collect_args/1]).	% used also by typer_options.erl

-include("dialyzer.hrl").

%%-----------------------------------------------------------------------

-type dial_cl_parse_ret() :: {'check_init', #options{}}
                           | {'plt_info', #options{}}
                           | {'cl', #options{}}
                           | {{'gui', 'gs' | 'wx'}, #options{}}
                           | {'error', string()}.

%%-----------------------------------------------------------------------

-spec start() -> dial_cl_parse_ret().

start() ->
  init(),
  Args = init:get_plain_arguments(),
  try
    cl(Args)
  catch
    throw:{dialyzer_cl_parse_error, Msg} -> {error, Msg};
    _:R ->
      Msg = io_lib:format("~p\n~p\n", [R, erlang:get_stacktrace()]),
      {error, lists:flatten(Msg)}
  end.

cl(["--add_to_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_add),
  cl(T);
cl(["--apps"|T]) ->
  T1 = get_lib_dir(T, []),
  {Args, T2} = collect_args(T1),
  append_var(dialyzer_options_files_rec, Args),
  cl(T2);
cl(["--build_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_build),
  cl(T);
cl(["--check_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_check),
  cl(T);
cl(["-n"|T]) ->
  cl(["--no_check_plt"|T]);
cl(["--no_check_plt"|T]) ->
  put(dialyzer_options_check_plt, false),
  cl(T);
cl(["--no_parallel"|T]) ->
  put(dialyzer_options_parallel, false),
  cl(T);
cl(["--slow_check_plt"|T]) ->
  put(dialyzer_options_fast_plt, false),
  cl(T);
cl(["-nn"|T]) ->
  cl(["--no_native"|T]);
cl(["--no_native"|T]) ->
  put(dialyzer_options_native, false),
  cl(T);
cl(["--plt_info"|T]) ->
  put(dialyzer_options_analysis_type, plt_info),
  cl(T);
cl(["--get_warnings"|T]) ->
  put(dialyzer_options_get_warnings, true),
  cl(T);
cl(["-D"|_]) ->
  error("No defines specified after -D");
cl(["-D"++Define|T]) ->
  Def = re:split(Define, "=", [{return, list}]),
  append_defines(Def),
  cl(T);
cl(["-h"|_]) ->
  help_message();
cl(["--help"|_]) ->
  help_message();
cl(["-I"]) ->
  error("no include directory specified after -I");
cl(["-I", Dir|T]) ->
  append_include(Dir),
  cl(T);
cl(["-I"++Dir|T]) ->
  append_include(Dir),
  cl(T);
cl(["-c"++_|T]) ->
  NewTail = command_line(T),
  cl(NewTail);
cl(["-r"++_|T0]) ->
  {Args, T} = collect_args(T0),
  append_var(dialyzer_options_files_rec, Args),
  cl(T);
cl(["--remove_from_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_remove),
  cl(T);
cl(["--com"++_|T]) ->
  NewTail = command_line(T),
  cl(NewTail);
cl(["--output"]) ->
  error("No outfile specified");
cl(["-o"]) ->
  error("No outfile specified");
cl(["--output",Output|T]) ->
  put(dialyzer_output, Output),
  cl(T);
cl(["--output_plt"]) ->
  error("No outfile specified for --output_plt");
cl(["--output_plt",Output|T]) ->
  put(dialyzer_output_plt, Output),
  cl(T);
cl(["-o", Output|T]) ->
  put(dialyzer_output, Output),
  cl(T);
cl(["-o"++Output|T]) ->
  put(dialyzer_output, Output),
  cl(T);
cl(["--raw"|T]) ->
  put(dialyzer_output_format, raw),
  cl(T);
cl(["--fullpath"|T]) ->
  put(dialyzer_filename_opt, fullpath),
  cl(T);
cl(["-pa", Path|T]) ->
  case code:add_patha(Path) of
    true -> cl(T);
    {error, _} -> error("Bad directory for -pa: "++Path)
  end;
cl(["--plt"]) ->
  error("No plt specified for --plt");
cl(["--plt", PLT|T]) ->
  put(dialyzer_init_plts, [PLT]),
  cl(T);
cl(["--plts"]) ->
  error("No plts specified for --plts");
cl(["--plts"|T]) ->
  {PLTs, NewT} = get_plts(T, []),
  put(dialyzer_init_plts, PLTs),
  cl(NewT);
cl(["-q"|T]) ->
  put(dialyzer_options_report_mode, quiet),
  cl(T);
cl(["--quiet"|T]) ->
  put(dialyzer_options_report_mode, quiet),
  cl(T);
cl(["--src"|T]) ->
  put(dialyzer_options_from, src_code),
  cl(T);
cl(["--no_spec"|T]) ->
  put(dialyzer_options_use_contracts, false),
  cl(T);
cl(["-v"|_]) ->
  io:format("Dialyzer version "++?VSN++"\n"),
  erlang:halt(?RET_NOTHING_SUSPICIOUS);
cl(["--version"|_]) ->
  io:format("Dialyzer version "++?VSN++"\n"),
  erlang:halt(?RET_NOTHING_SUSPICIOUS);
cl(["--verbose"|T]) ->
  put(dialyzer_options_report_mode, verbose),
  cl(T);
cl(["-W"|_]) ->
  error("-W given without warning");
cl(["-Whelp"|_]) ->
  help_warnings();
cl(["-W"++Warn|T]) ->
  append_var(dialyzer_warnings, [list_to_atom(Warn)]),
  cl(T);
cl(["--dump_callgraph"]) ->
  error("No outfile specified for --dump_callgraph");
cl(["--dump_callgraph", File|T]) ->
  put(dialyzer_callgraph_file, File),
  cl(T);
cl(["--gui"|T]) ->
  put(dialyzer_options_mode, {gui, gs}),
  cl(T);
cl(["--wx"|T]) ->
  put(dialyzer_options_mode, {gui, wx}),
  cl(T);
cl([H|_] = L) ->
  case filelib:is_file(H) orelse filelib:is_dir(H) of
    true ->
      NewTail = command_line(L),
      cl(NewTail);
    false ->
      error("Unknown option: " ++ H)
  end;
cl([]) ->
  {RetTag, Opts} =
    case get(dialyzer_options_analysis_type) =:= plt_info of
      true ->
	put(dialyzer_options_analysis_type, plt_check),
	{plt_info, cl_options()};
      false ->
	case get(dialyzer_options_mode) of
	  {gui, _} = GUI -> {GUI, common_options()};
	  cl ->
	    case get(dialyzer_options_analysis_type) =:= plt_check of
	      true  -> {check_init, cl_options()};
	      false -> {cl, cl_options()}
	    end
	end
    end,
  case dialyzer_options:build(Opts) of
    {error, Msg} -> error(Msg);
    OptsRecord -> {RetTag, OptsRecord}
  end.

%%-----------------------------------------------------------------------

command_line(T0) ->
  {Args, T} = collect_args(T0),
  append_var(dialyzer_options_files, Args),
  %% if all files specified are ".erl" files, set the 'src' flag automatically
  case lists:all(fun(F) -> filename:extension(F) =:= ".erl" end, Args) of
    true -> put(dialyzer_options_from, src_code);
    false -> ok
  end,
  T.

error(Str) ->
  Msg = lists:flatten(Str),
  throw({dialyzer_cl_parse_error, Msg}).

init() ->
  put(dialyzer_options_mode, cl),
  put(dialyzer_options_files_rec, []),
  put(dialyzer_options_report_mode, normal),
  put(dialyzer_warnings, []),
  DefaultOpts = #options{},
  put(dialyzer_include,           DefaultOpts#options.include_dirs),
  put(dialyzer_options_defines,   DefaultOpts#options.defines),
  put(dialyzer_options_files,     DefaultOpts#options.files),
  put(dialyzer_output_format,     formatted),
  put(dialyzer_filename_opt,      basename),
  put(dialyzer_options_check_plt, DefaultOpts#options.check_plt),
  put(dialyzer_options_fast_plt,  DefaultOpts#options.fast_plt),
  put(dialyzer_options_parallel,  DefaultOpts#options.parallel_mode),
  ok.

append_defines([Def, Val]) ->
  {ok, Tokens, _} = erl_scan:string(Val++"."),
  {ok, ErlVal} = erl_parse:parse_term(Tokens),
  append_var(dialyzer_options_defines, [{list_to_atom(Def), ErlVal}]);
append_defines([Def]) ->
  append_var(dialyzer_options_defines, [{list_to_atom(Def), true}]).

append_include(Dir) ->
  append_var(dialyzer_include, [Dir]).

append_var(Var, List) when is_list(List) ->
  put(Var, get(Var) ++ List),
  ok.

%%-----------------------------------------------------------------------

-spec collect_args([string()]) -> {[string()], [string()]}.

collect_args(List) ->
  collect_args_1(List, []).

collect_args_1(["-"++_|_] = L, Acc) ->
  {lists:reverse(Acc), L};
collect_args_1([Arg|T], Acc) ->
  collect_args_1(T, [Arg|Acc]);
collect_args_1([], Acc) ->
  {lists:reverse(Acc), []}.

%%-----------------------------------------------------------------------

cl_options() ->
  [{files, get(dialyzer_options_files)},
   {files_rec, get(dialyzer_options_files_rec)},
   {output_file, get(dialyzer_output)},
   {output_format, get(dialyzer_output_format)},
   {filename_opt, get(dialyzer_filename_opt)},
   {analysis_type, get(dialyzer_options_analysis_type)},
   {get_warnings, get(dialyzer_options_get_warnings)},
   {callgraph_file, get(dialyzer_callgraph_file)}
   |common_options()].

common_options() ->
  [{defines, get(dialyzer_options_defines)},
   {from, get(dialyzer_options_from)},
   {include_dirs, get(dialyzer_include)},
   {plts, get(dialyzer_init_plts)},
   {output_plt, get(dialyzer_output_plt)},
   {report_mode, get(dialyzer_options_report_mode)},
   {use_spec, get(dialyzer_options_use_contracts)},
   {warnings, get(dialyzer_warnings)},
   {check_plt, get(dialyzer_options_check_plt)},
   {fast_plt, get(dialyzer_options_fast_plt)},
   {parallel_mode, get(dialyzer_options_parallel)}].

%%-----------------------------------------------------------------------

get_lib_dir([H|T], Acc) ->
  NewElem =
    case code:lib_dir(list_to_atom(H)) of
      {error, bad_name} ->
	case H =:= "erts" of % hack for including erts in an un-installed system
	  true -> filename:join(code:root_dir(), "erts/preloaded/ebin");
	  false -> H
	end;
      LibDir -> LibDir ++ "/ebin"
    end,
  get_lib_dir(T, [NewElem|Acc]);
get_lib_dir([], Acc) ->
  lists:reverse(Acc).

%%-----------------------------------------------------------------------

get_plts(["--"|T], Acc) -> {lists:reverse(Acc), T};
get_plts(["-"++_Opt = H|T], Acc) -> {lists:reverse(Acc), [H|T]};
get_plts([H|T], Acc) -> get_plts(T, [H|Acc]);
get_plts([], Acc) -> {lists:reverse(Acc), []}.

%%-----------------------------------------------------------------------

help_warnings() ->
  S = warning_options_msg(),
  io:put_chars(S),
  erlang:halt(?RET_NOTHING_SUSPICIOUS).

help_message() ->
  S = "Usage: dialyzer [--help] [--version] [--shell] [--quiet] [--verbose]
		[-pa dir]* [--plt plt] [--plts plt*] [-Ddefine]*
                [-I include_dir]* [--output_plt file] [-Wwarn]*
                [--src] [--gui | --wx] [files_or_dirs] [-r dirs]
                [--apps applications] [-o outfile]
		[--build_plt] [--add_to_plt] [--remove_from_plt]
		[--check_plt] [--no_check_plt] [--plt_info] [--get_warnings]
                [--no_native] [--no_parallel] [--slow_check_plt] [--fullpath]
Options:
  files_or_dirs (for backwards compatibility also as: -c files_or_dirs)
      Use Dialyzer from the command line to detect defects in the
      specified files or directories containing .erl or .beam files,
      depending on the type of the analysis.
  -r dirs
      Same as the previous but the specified directories are searched
      recursively for subdirectories containing .erl or .beam files in
      them, depending on the type of analysis.
  --apps applications
      Option typically used when building or modifying a plt as in:
        dialyzer --build_plt --apps erts kernel stdlib mnesia ...
      to conveniently refer to library applications corresponding to the
      Erlang/OTP installation. However, the option is general and can also
      be used during analysis in order to refer to Erlang/OTP applications.
      In addition, file or directory names can also be included, as in:
        dialyzer --apps inets ssl ./ebin ../other_lib/ebin/my_module.beam
  -o outfile (or --output outfile)
      When using Dialyzer from the command line, send the analysis
      results to the specified outfile rather than to stdout.
  --raw
      When using Dialyzer from the command line, output the raw analysis
      results (Erlang terms) instead of the formatted result.
      The raw format is easier to post-process (for instance, to filter
      warnings or to output HTML pages).
  --src
      Override the default, which is to analyze BEAM files, and
      analyze starting from Erlang source code instead.
  -Dname (or -Dname=value)
      When analyzing from source, pass the define to Dialyzer. (**)
  -I include_dir
      When analyzing from source, pass the include_dir to Dialyzer. (**)
  -pa dir
      Include dir in the path for Erlang (useful when analyzing files
      that have '-include_lib()' directives).
  --output_plt file
      Store the plt at the specified file after building it.
  --plt plt
      Use the specified plt as the initial plt (if the plt was built 
      during setup the files will be checked for consistency).
  --plts plt*
      Merge the specified plts to create the initial plt -- requires
      that the plts are disjoint (i.e., do not have any module
      appearing in more than one plt).
      The plts are created in the usual way:
        dialyzer --build_plt --output_plt plt_1 files_to_include
        ...
        dialyzer --build_plt --output_plt plt_n files_to_include
      and then can be used in either of the following ways:
        dialyzer files_to_analyze --plts plt_1 ... plt_n
      or:
        dialyzer --plts plt_1 ... plt_n -- files_to_analyze
      (Note the -- delimiter in the second case)
  -Wwarn
      A family of options which selectively turn on/off warnings
      (for help on the names of warnings use dialyzer -Whelp).
  --shell
      Do not disable the Erlang shell while running the GUI.
  --version (or -v)
      Print the Dialyzer version and some more information and exit.
  --help (or -h)
      Print this message and exit.
  --quiet (or -q)
      Make Dialyzer a bit more quiet.
  --verbose
      Make Dialyzer a bit more verbose.
  --build_plt
      The analysis starts from an empty plt and creates a new one from the
      files specified with -c and -r. Only works for beam files.
      Use --plt(s) or --output_plt to override the default plt location.
  --add_to_plt
      The plt is extended to also include the files specified with -c and -r.
      Use --plt(s) to specify which plt to start from, and --output_plt to
      specify where to put the plt. Note that the analysis might include
      files from the plt if they depend on the new files.
      This option only works with beam files.
  --remove_from_plt
      The information from the files specified with -c and -r is removed
      from the plt. Note that this may cause a re-analysis of the remaining
      dependent files.
  --check_plt
      Check the plt for consistency and rebuild it if it is not up-to-date.
      Actually, this option is of rare use as it is on by default.
  --slow_plt_check
      Do not perform incremental check of the plt (for debugging purposes only).
  --no_parallel
      Perform serial instead of parallel analysis.
   --no_check_plt (or -n)
      Skip the plt check when running Dialyzer. Useful when working with
      installed plts that never change.
  --plt_info
      Make Dialyzer print information about the plt and then quit. The plt
      can be specified with --plt(s).
  --get_warnings
      Make Dialyzer emit warnings even when manipulating the plt. Warnings
      are only emitted for files that are actually analyzed.
  --dump_callgraph file
      Dump the call graph into the specified file whose format is determined
      by the file name extension. Supported extensions are: raw, dot, and ps.
      If something else is used as file name extension, default format '.raw'
      will be used.
  --no_native (or -nn)
      Bypass the native code compilation of some key files that Dialyzer
      heuristically performs when dialyzing many files; this avoids the
      compilation time but it may result in (much) longer analysis time.
  --fullpath
      Display the full path names of files for which warnings are emitted.
  --gui
      Use the gs-based GUI.
  --wx
      Use the wx-based GUI.

Note:
  * denotes that multiple occurrences of these options are possible.
 ** options -D and -I work both from command-line and in the Dialyzer GUI;
    the syntax of defines and includes is the same as that used by \"erlc\".

" ++ warning_options_msg() ++ "
The exit status of the command line version is:
  0 - No problems were encountered during the analysis and no
      warnings were emitted.
  1 - Problems were encountered during the analysis.
  2 - No problems were encountered, but warnings were emitted.
",
  io:put_chars(S),
  erlang:halt(?RET_NOTHING_SUSPICIOUS).

warning_options_msg() ->
  "Warning options:
  -Wno_return
     Suppress warnings for functions that will never return a value.
  -Wno_unused
     Suppress warnings for unused functions.
  -Wno_improper_lists
     Suppress warnings for construction of improper lists.
  -Wno_tuple_as_fun
     Suppress warnings for using tuples instead of funs.
  -Wno_fun_app
     Suppress warnings for fun applications that will fail.
  -Wno_match
     Suppress warnings for patterns that are unused or cannot match.
  -Wno_opaque
     Suppress warnings for violations of opaqueness of data types.
  -Wunmatched_returns ***
     Include warnings for function calls which ignore a structured return
     value or do not match against one of many possible return value(s).
  -Werror_handling ***
     Include warnings for functions that only return by means of an exception.
  -Wrace_conditions ***
     Include warnings for possible race conditions.
  -Wbehaviours ***
     Include warnings about behaviour callbacks which drift from the published
     recommended interfaces.
  -Wunderspecs ***
     Warn about underspecified functions
     (those whose -spec is strictly more allowing than the success typing).

The following options are also available but their use is not recommended:
(they are mostly for Dialyzer developers and internal debugging)
  -Woverspecs ***
     Warn about overspecified functions
     (those whose -spec is strictly less allowing than the success typing).
  -Wspecdiffs ***
     Warn when the -spec is different than the success typing.

*** Identifies options that turn on warnings rather than turning them off.
".
