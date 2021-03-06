% Holds the logic responsible for defining overridable functions and handling super.
-module(elixir_overridable).
-export([setup/1, overridable/1, overridable/2, super/4, store_pending/1, format_error/1]).
-include("elixir.hrl").
-define(attr, {elixir, overridable}).

setup(Module) ->
  overridable(Module, #{}).

overridable(Module) ->
  ets:lookup_element(elixir_module:data_table(Module), ?attr, 2).

overridable(Module, Value) ->
  ets:insert(elixir_module:data_table(Module), {?attr, Value}).

super(Meta, File, Module, Function) ->
  case store(Module, Function, true) of
    {_, _} = KindName ->
      KindName;
    error ->
      elixir_errors:form_error(Meta, File, ?MODULE, {no_super, Module, Function})
  end.

store_pending(Module) ->
  [begin
    {_, _} = store(Module, Pair, false),
    Pair
   end || {Pair, {_, _, _, false}} <- maps:to_list(overridable(Module)),
          not 'Elixir.Module':'defines?'(Module, Pair)].

%% Private

store(Module, Function, Hidden) ->
  Overridable = overridable(Module),
  case maps:find(Function, Overridable) of
    {ok, {Count, Def, Neighbours, Overridden}} ->
      {{{def, {Name, Arity}}, Kind, Meta, File, _Check,
       {Defaults, _HasBody, _LastDefaults}}, Clauses} = Def,

      {FinalKind, FinalName, FinalArity, FinalClauses} =
        case Hidden of
          false ->
            {Kind, Name, Arity, Clauses};
          true when Kind == defmacro; Kind == defmacrop ->
            {defmacrop, name(Name, Count), Arity, Clauses};
          true ->
            {defp, name(Name, Count), Arity, Clauses}
        end,

      Tuple = {FinalName, FinalArity},

      case Overridden of
        false ->
          overridable(Module, maps:put(Function, {Count, Def, Neighbours, true}, Overridable)),
          (not elixir_compiler:get_opt(internal)) andalso
            'Elixir.Module.LocalsTracker':reattach(Module, Kind, Function, Neighbours),
          elixir_def:store_definition(false, FinalKind, Meta, FinalName, FinalArity,
                                      File, Module, Defaults, FinalClauses),
          elixir_locals:record_definition(Tuple, FinalKind, Module),
          elixir_locals:record_local(Tuple, Module, Function);
        true ->
          ok
      end,

      {FinalKind, FinalName};
    error ->
      error
  end.

name(Name, Count) when is_integer(Count) ->
  list_to_atom(atom_to_list(Name) ++ " (overridable " ++ integer_to_list(Count) ++ ")").

%% Error handling

format_error({no_super, Module, {Name, Arity}}) ->
  Bins   = [format_fa(X) || {X, {_, _, _, _}} <- maps:to_list(overridable(Module))],
  Joined = 'Elixir.Enum':join(Bins, <<", ">>),
  io_lib:format("no super defined for ~ts/~B in module ~ts. Overridable functions available are: ~ts",
    [Name, Arity, elixir_aliases:inspect(Module), Joined]).

format_fa({Name, Arity}) ->
  A = 'Elixir.Inspect.Function':escape_name(Name),
  B = integer_to_binary(Arity),
  <<A/binary, $/, B/binary>>.
