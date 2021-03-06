:- module(scasp, [
	load/1,
	main/1,
	run_defined_query/0,
	'??'/1,
	solve/4,
	check_goal/4,
	solve_goal/4,
	solve_goal_forall/4,
	solve_goal_table_predicate/4,
	solve_goal_predicate/4,
	solve_goal_builtin/4,
	check_CHS/3,
	predicate/1,
	table_predicate/1,
	my_copy_term/4,
	check_calls/0,
	pos_loops/0,
	print_on/0
		    ]).

%% ------------------------------------------------------------- %%
:- use_package(assertions).
:- doc(title, "Meta interpreter under stable model semantics").
:- doc(author, "Joaquin Arias").
:- doc(filetype, module).

:- doc(module, "

This module contains the main functionality of @apl{scasp}.

@pred{load/1} is the predicate used to load the constraint logic
program.

@pred{solve/4} is the predicate used to evaluate the query of a
program under the stable model semantic.

").

%% ------------------------------------------------------------- %%
:- use_module(scasp_io).
:- reexport(scasp_io, [
	pr_rule/2,
	pr_query/1,
	pr_user_predicate/1,
	pr_table_predicate/1,
	write_program/0
			 ]).

:- use_module(clp_call_stack).
:- op(700, xfx, ['~>', '<~']).
:- reexport(clp_call_stack, [
	'~>'/2,
	'<~'/2
			    ]).

:- use_module(clp_disequality_rt).
:- op(700, xfx, [(.\=.),(.=.)]).

:- use_module(clp_clpq).

%:- use_package(clpfd).
%:- use_package(clpq).
:- use_module(library(formulae)).
%:- use_module(library(read)).
%:- use_module(library(format)).
%:- use_module(library(dynamic)).

:- op(700, fx,  [not,(?=), (??)]).

%% ------------------------------------------------------------- %%
:- doc(section, "Main predicates").

% :- use_package(tabling).  
% :- active_tclp.
% :- table solve_goal_table_predicate/4.% , solve_goal_predicate/4.

:- pred load(Files) : list(Files) #"Loads a list of files".

load(X) :-
%	abolish_all_tables,
	load_program(X),
	true.

:- pred main(Args) : list(Args) #"Used when calling from command line
by passing the command line options and the input files".

main(Args) :-
	print_on,
	retractall(current_option(_,_)),
	retractall(counter(_,_)),
	parse_args(Args, Options, Sources),
	set_options(Options),
	load(Sources),
	if_user_option(write_program, write_program),
	if_user_option(write_program, halt),
	(
	    current_option(interactive, on) ->
	    main_loop
	;
	    defined_query(Q),
	    main_solve(Q)
	).
main(_).

main_loop :-
	print('\n?- '),
	catch(read(R),_,fail_main_loop),
	conj_to_list(R,Q),
	(
	    member(exit, Q) ->
	    halt
	;
	    (
		main_solve(Q) ->
		nl, main_loop
	    ;
		print('\nfalse'),
		main_loop
	    )
	).

fail_main_loop :-
	print('\nno'),
	main_loop.

main_solve(Q) :-
	current_option(answers,Number),
	init_counter,
	process_query(Q,Query),
	statistics(runtime,_),
	solve(Query, [], StackOut, Model),
	statistics(runtime, [_|[T]]),
	increase_counter,
	answer_counter(Counter),
	format('\nAnswer ~w\t(in ~w ms):',[Counter,T]),
	if_user_option(print,print_output(StackOut)),
	print_model(Model),nl,
	print(Q),
	(
	    Number = -1,
	    allways_ask_for_more_models,nl,nl
	;
	    Number = 0,
	    nl,nl,
	    fail
	;
	    Number > 0,
	    nl,nl,
	    Counter = Number
	).
	

:- pred run_defined_query #"Used from the interactive mode to run
the defined query".

run_defined_query :-
	defined_query(A),
	solve_query(A),
	print(A),
	allways_ask_for_more_models,nl,nl.

defined_query(_) :-
	pr_query([not(o_false)]), !,
	format('\nQuery not defined\n',[]),
	fail.
defined_query(Q) :-
	pr_query(Q),
	format('\nDefault query:\n\t?- ~w.\n',Q).

%% ------------------------------------------------------------- %%
:- doc(section, "Top Level Predicates").

:- pred check_calls/0 #"Turn on the flag @var{check_calls}".
:- pred pos_loops/0 #"Turn on the flag @var{pos_loops}".
:- pred print_on/0 #"Turn on the flag @var{print}".

check_calls :- 	set(check_calls,on).
pos_loops :- 	set(pos_loops,on).
print_on :- 	set(print,on).

:- pred ??(Query) : list(Query) #"Shorcut predicate to ask queries in
the top-level. It calls solve_query/1".

?? Q :- solve_query(Q).

solve_query(A) :-
	process_query(A,Query),
	statistics(runtime,_),
	solve(Query, [], StackOut, Model),
	statistics(runtime, [_|T]),
	format('\nsolve_run_time = ~w ms\n\n',T),
	if_user_option(print,print_output(StackOut)),
	print_model(Model),nl,nl,
	ask_for_more_models.

%% ------------------------------------------------------------- %%
:- doc(section, "Predicates to solve the query").

:- pred solve(Goals, StackIn, StackOut, Model) #"Solve the list of
sub-goals @var{Goal} where @var{StackIn} is the list of goals already
visited and returns in @var{StackOut} the list of goals visited to
prove the sub-goals and in @var{Model} the model with support the
sub-goals".

solve([], StackIn, [[]|StackIn], []).
solve([Goal|Goals], StackIn, StackOut, Model) :-
	if_user_option(check_calls, print_check_calls_calling(Goal,StackIn)),
	check_goal(Goal, StackIn, StackMid, Modelx), Modelx = [AddGoal|JGoal],
	if_user_option(check_calls, format('Succes  ~p\n',[Goal])),
	solve(Goals, StackMid, StackOut, Modelxs), Modelxs = JGoals,
	(
	    shown_predicate(Goal) ->
	    Model = [AddGoal, JGoal|JGoals]
	;
%	    Model = [AddGoal, JGoal|JGoals]
	    Model = [JGoal|JGoals]
	).

:- pred check_goal(Goal, StackIn, StackOut, Model) #"Call
@pred{check_CHS/3} to check the sub-goal @var{Goal} against the list
of goals already visited @var{StackIn} to determine if it is a
coinductive success, a coinductive failure, an already proved
sub-goal, or if it has to be evaluated".

check_goal(Goal, StackIn, StackOut, Model) :-
	check_CHS(Goal, StackIn, Check),  %% Check condition for coinductive success
	(
	    Check == 1, %% coinduction success <- cycles containing even loops may succeed
	    StackOut = [[],chs(Goal)|StackIn],
	    JGoal = [],
	    AddGoal = chs(Goal)
	;
	    Check == 2, %% already proved in the stack
	    StackOut = [[],proved(Goal)|StackIn],
	    JGoal = [],
	    AddGoal = proved(Goal)
	;
	    Check == 0, %% coinduction does neither success nor fails <- the execution continues inductively
	    solve_goal(Goal, StackIn, StackOut, Modelx), Modelx = [Goal|JGoal],
	    AddGoal = Goal
	;
	    Check == -1, %% coinduction fails <- the negation of a call unifies with a call in the call stack
	    fail
	),
	Model = [AddGoal|JGoal].

:- pred solve_goal(Goal, StackIn, StackOut, GoalModel) #"Solve a
simple sub-goal @var{Goal} where @var{StackIn} is the list of goals
already visited and returns in @var{StackOut} the list of goals
visited to prove the sub-goals and in @var{Model} the model with
support the sub-goals".

solve_goal(Goal, StackIn, StackOut, GoalModel) :-
	Goal = forall(_,_), 
	solve_goal_forall(Goal, [Goal|StackIn], StackOut, Model),
	GoalModel = [Goal|Model].
solve_goal(Goal, StackIn, [[],Goal|StackIn], GoalModel) :-
	Goal = not(is(V,Expresion)), 
	NV is Expresion,
	V .\=. NV,
	GoalModel = [Goal].
solve_goal(Goal, StackIn, StackOut, Model) :-
	Goal \= [], Goal \= [_|_], Goal \= forall(_, _), Goal \= not(is(_,_)),Goal \= builtin(_),
	table_predicate(Goal), 
	AttStackIn <~ stack([Goal|StackIn]),
	solve_goal_table_predicate(Goal, AttStackIn, AttStackOut, AttModel),
	AttStackOut ~> stack(StackOut),
	AttModel ~> model(Model).
solve_goal(Goal, StackIn, StackOut, Model) :-
	Goal \= [], Goal \= [_|_], Goal \= forall(_, _), Goal \= not(is(_,_)),Goal \= builtin(_),
	\+ table_predicate(Goal),
	predicate(Goal), 
	solve_goal_predicate(Goal, [Goal|StackIn], StackOut, Model).
solve_goal(Goal, StackIn, [[],Goal|StackOut], Model) :-
	Goal \= [], Goal \= [_|_], Goal \= forall(_, _), Goal \= not(is(_,_)), \+ predicate(Goal),
	\+ table_predicate(Goal),
	solve_goal_builtin(Goal, StackIn, StackOut, Model).

:- pred solve_goal_forall(forall(Var,Goal), StackIn, StackOut,
GoalModel) #"Solve a sub-goal of the form @var{forall(Var,Goal)} and
success if @var{Var} success in all its domain for the goal
@var{Goal}. It calls @pred{solve/4}".

solve_goal_forall(forall(Var, Goal), StackIn, [[]|StackOut], Model) :-
	my_copy_term(Var,Goal,NewVar,NewGoal),
	my_copy_term(Var,Goal,NewVar2,NewGoal2),
	solve([NewGoal], StackIn, [[]|StackMid], ModelMid),
	check_unbound(NewVar, List), !,
	(
	    List == [] ->
	    StackOut = StackMid,
	    Model = ModelMid
	;
	    List = 'clpq'(NewVar3,Constraints) ->
	    dual_clpq(Constraints, ConDual),
	    if_user_option(check_calls, format('Executing ~p with clpq Constraint = ~p\n', [Goal, ConDual])),
	    exec_with_clpq_constraints(NewVar2, NewGoal2, 'entry'(NewVar3,[]),'dual'(NewVar3,ConDual), StackMid, StackOut, ModelList),
	    append(ModelMid, ModelList, Model)
	;
	    if_user_option(check_calls, format('Executing ~p with clp_disequeality list = ~p\n', [Goal, List])),
	    exec_with_neg_list(NewVar2, NewGoal2, List, StackMid, StackOut, ModelList),
	    append(ModelMid, ModelList, Model)
	).

check_unbound(Var, _) :-
	ground(Var), !, fail.
check_unbound(Var, List) :-
	get_neg_var(Var, List), !.
check_unbound(Var, 'clpq'(NewVar,Constraints)) :-
	dump_clpq_var([Var],[NewVar],Constraints),
	Constraints \== [], !.
check_unbound(Var, []) :-
	var(Var), !.

exec_with_clpq_constraints(Var, Goal, 'entry'(ConVar, ConEntry),'dual'(ConVar, ConDual), StackIn, StackOut, Model) :-
	my_copy_term(Var, [Goal, StackIn], NewVar, [NewGoal,NewStackIn]),
	append(ConEntry, ConDual, Con),
	my_copy_term(ConVar, Con, NewConVar, NewCon),
	NewVar = ConVar,
	apply_clpq_constraints(Con),
	if_user_option(check_calls, format('Executing ~p with clpq_constrains ~p\n',[NewGoal,Con])),
	solve([NewGoal], NewStackIn, [[]|NewStackMid], ModelMid),
	if_user_option(check_calls, format('Success executing ~p with constrains ~p\n',[NewGoal,Con])),
	(
	    entails(NewVar, (NewConVar, NewCon)) ->
	    StackOut = NewStackMid,
	    Model = ModelMid
	;
	    dump_clpq_var([NewVar], [NewConVar], ExitCon),
	    dual_clpq(ExitCon, NewConDual),
	    exec_with_clpq_constraints(Var, Goal, 'entry'(NewConVar, NewCon),'dual'(NewConVar, NewConDual), NewStackMid, StackOut, Models),
	    append(ModelMid,Models,Model)
	).

exec_with_neg_list(_,   _,    [],         StackIn, StackIn, []).
exec_with_neg_list(Var, Goal, [Value|Vs], StackIn, StackOut, Model) :-
	my_copy_term(Var, [Goal,StackIn], NewVar, [NewGoal,NewStackIn]),
	NewVar = Value,
	if_user_option(check_calls, format('Executing ~p with value ~p\n',[NewGoal,Value])),
	solve([NewGoal], NewStackIn, [[]|NewStackMid], ModelMid), 
	if_user_option(check_calls, format('Success executing ~p with value ~p\n',[NewGoal,Value])),
	exec_with_neg_list(Var, Goal, Vs, NewStackMid, StackOut, Models),
	append(ModelMid,Models,Model).

:- pred solve_goal_table_predicate(Goal, AttStackIn, AttStackOut,
AttModel) #"Used to evaluate predicates under tabling. This predicates
should be defined in the program using the directive @em{#table
pred/n.}".

%% TABLED to avoid loops and repeated answers
solve_goal_table_predicate(Goal, AttStackIn, AttStackOut, AttModel) :-
	pr_rule(Goal, Body),
	AttStackIn ~> stack(StackIn),
	solve(Body, StackIn, StackOut, Model),
	AttStackOut <~ stack(StackOut),
	AttModel <~ model([Goal|Model]).
%% TABLED to avoid loops and repeated answers

:- pred solve_goal_predicate(Goal, StackIn, StackOut, GoalModel)
#"Used to evaluate a user predicate".

solve_goal_predicate(Goal, StackIn, StackOut, GoalModel) :-
	pr_rule(Goal, Body),
	solve(Body, StackIn, StackOut, BodyModel),
	GoalModel = [Goal|BodyModel].

:- pred solve_goal_builtin(Goal, StackIn, StackOut, AttModel) #"Used
to evaluate builtin predicates predicate".

solve_goal_builtin(builtin(Goal), StackIn, StackIn, Model) :- !,
	exec_goal(Goal),
	Model = [builtin(Goal)].
solve_goal_builtin(Goal, StackIn, StackIn, Model) :-
	Goal =.. [Op|_],
	member(Op,[.=., .<>., .<., .>., .>=., .=<.]), !,
	exec_goal(apply_clpq_constraints(Goal)),
	Model = [Goal].
solve_goal_builtin(Goal, StackIn, StackIn, Model) :- 
	exec_goal(Goal),
	Model = [Goal].

exec_goal(A \= B) :- !,
	if_user_option(check_calls, format('exec ~p \\= ~p\n',[A,B])),
	.\=.(A, B),
	if_user_option(check_calls, format('ok   ~p \\= ~p\n', [A,B])).
exec_goal(Goal) :-
	if_user_option(check_calls, format('exec goal ~p \n',[Goal])),
	catch(call(Goal),_,fail),
	if_user_option(check_calls, format('ok   goal ~p \n', [Goal])).


:- pred check_CHS(Goal, StackIn, Result) #"Checks the @var{StackIn}
and returns in @var{Result} if the goal @var{Goal} is a coinductive
success, a coinductive failure or an already proved goal. Otherwise it
is constraint against its negation atoms already visited".

%% inmediate success if the goal has already been proved.
check_CHS(Goal, I, 2) :-
	predicate(Goal),
	ground(Goal),
	\+ \+ proved_in_stack(Goal, I), !.
%% coinduction success <- cycles containing even loops may succeed
check_CHS(Goal, I, 1) :-
	predicate(Goal),
	\+ \+ type_loop(Goal, I, even), !.
%% coinduction fails <- the goal is entailed by its negation in the
%% call stack
check_CHS(Goal, I, -1) :-
	predicate(Goal),
	\+ \+ neg_in_stack(Goal, I), !,
	if_user_option(check_calls, format('Negation of the goal in the stack, failling (Goal = ~w)\n',[Goal])).
%% coinduction fails <- cycles containing positive loops can be solve
%% using tabling
check_CHS(Goal, I, -1) :-
	predicate(Goal),
	\+ table_predicate(Goal),
	\+ \+ type_loop(Goal, I, pos), !,
	if_user_option(check_calls, format('Positive loop, failling (Goal = ~w)\n',[Goal])),
	if_user_option(pos_loops, format('Warning positive loop failling (Goal = ~w)\n',[Goal])).
%% coinduction does not success or fails <- the execution continues
%% inductively
check_CHS(Goal, I, 0) :-
	predicate(Goal),
	if_user_option(check_calls, format('Enter ground_neg_in_stack for ~p\n',[Goal])),
	ground_neg_in_stack(Goal, I), 
	if_user_option(check_calls, format('\tThere exit the negation of ~p\n\n',[Goal])).
check_CHS(Goal, I, 0) :-
	predicate(Goal),
	\+ ground_neg_in_stack(Goal,I),
	true.
check_CHS(Goal, _I, 0) :-
	\+ predicate(Goal),
	true.

%% check if the negation is in the stack -> coinductive failure
neg_in_stack(Goal, [NegGoal|_]) :-
	(
	    not(Goal) == NegGoal
	;
	    Goal == not(NegGoal)
	), !.
neg_in_stack(Goal, [_|Ss]) :-
	neg_in_stack(Goal, Ss).

%% ground_neg_in_stack
ground_neg_in_stack(Goal, S) :-
	ground_neg_in_stack_(Goal, S, 0, -1, Flag),
	Flag == found,
	if_user_option(check_calls, format('\tGoal unified with its negation in the stack\n',[Goal])).
	
ground_neg_in_stack_(_,[],_,_, _Flag) :- !.
ground_neg_in_stack_(Goal, [[]|Ss], Intervening, MaxInter, Flag) :- !,
	NewInter is Intervening - 1,
	ground_neg_in_stack_(Goal, Ss, NewInter, MaxInter, Flag).
ground_neg_in_stack_(Goal, [chs(not(NegGoal))|Ss], Intervening, MaxInter, found) :-
	Intervening =< MaxInter,
	Goal =.. [Name|ArgGoal],
	NegGoal =.. [Name|ArgNegGoal], !,
	loop_list_disunification(ArgGoal, ArgNegGoal), 
	max(MaxInter, Intervening, NewMaxInter),
	NewInter is Intervening + 1,
	ground_neg_in_stack_(Goal, Ss, NewInter, NewMaxInter, found).
ground_neg_in_stack_(not(Goal), [chs(NegGoal)|Ss], Intervening, MaxInter, found) :-
	Intervening =< MaxInter,
	Goal =.. [Name|ArgGoal],
	NegGoal =.. [Name|ArgNegGoal], !, 
	loop_list_disunification(ArgGoal, ArgNegGoal),
	max(MaxInter, Intervening, NewMaxInter),
	NewInter is Intervening + 1,
	ground_neg_in_stack_(not(Goal), Ss, NewInter, NewMaxInter, found).
ground_neg_in_stack_(Goal, [_|Ss], Intervening, MaxInter, Flag) :- !,
	max(MaxInter, Intervening, NewMaxInter),
	NewInter is Intervening + 1,	
	ground_neg_in_stack_(Goal, Ss, NewInter, NewMaxInter, Flag).

%% proved_in_stack
proved_in_stack(Goal, S) :-
	proved_in_stack_(Goal, S, 0, -1),
	if_user_option(check_calls, format('\tGoal ~p is already in the stack\n',[Goal])).
proved_in_stack_(Goal, [[]|Ss], Intervening, MaxInter) :- 
	NewInter is Intervening - 1,
	proved_in_stack_(Goal, Ss, NewInter, MaxInter).
proved_in_stack_(Goal, [S|_], Intervening, MaxInter) :-
	S \= [],
	Goal == S, !,
	Intervening =< MaxInter.
proved_in_stack_(Goal, [S|Ss], Intervening, MaxInter) :-
	S \= [],
	max(MaxInter, Intervening, NewMaxInter),
	NewInter is Intervening + 1,
	proved_in_stack_(Goal, Ss, NewInter, NewMaxInter).

max(A,B,A) :-
	A >= B.
max(A,B,B) :-
	A < B.

%% check if it is a even loop -> coinductive success
type_loop(Goal, Stack, Type) :-
	Goal \= not(_),
	Intervening = 0,
	NumberNegation = 0,
	type_loop_(Goal, Intervening, NumberNegation, Stack, Type).
type_loop(not(Goal), Stack, Type) :-
	Intervening = 0,
	NumberNegation = 1,
	type_loop_(not(Goal), Intervening, NumberNegation, Stack, Type).

type_loop_(Goal, Iv, N, [[]|Ss], Type) :- !,
	NewIv is Iv - 1,
	type_loop_(Goal, NewIv, N, Ss, Type).
type_loop_(Goal, Iv, N, [_S|Ss], Type) :-
	Iv < 0,
	NewIv is Iv + 1,
	type_loop_(Goal, NewIv, N, Ss, Type).
type_loop_(Goal, 0, N, [S|_],pos) :- Goal = S, N = 0.
type_loop_(not(Goal), 0, N, [not(S)|_],even) :- Goal == S, !, N > 0, 1 is mod(N, 2).
type_loop_(Goal, 0, N, [S|_],even) :- Goal == S, N > 0, 0 is mod(N, 2).
type_loop_(Goal, 0, N, [S|Ss],Type) :-
	Goal \== S,
	S = not(_),
	NewN is N + 1,
	type_loop_(Goal, 0, NewN, Ss,Type).
type_loop_(Goal, 0, N, [S|Ss], Type) :-
	Goal \== S,
	S \= not(_),
	type_loop_(Goal, 0, N, Ss,Type).

%% ------------------------------------------------------------- %%
:- doc(section, "Auxiliar Predicates").

:- pred predicate(Goal) #"Success if @var(Goal) is a user
predicate".

%% Check if the goal Goal is a user defined predicate
predicate(builtin(_)) :- !, fail.
predicate(not(_ is _)) :- !, fail.
predicate(not(_)) :- !.
predicate(Goal) :-
	Goal =.. [Name|Args],
	length(Args,La),
	pr_user_predicate(Name/La), !.
%% predicate(-_Goal) :- !. %% NOTE that -goal is translated as '-goal' 

:- pred table_predicate(Goal) #"Success if @var(Goal) is defined as
a tabled predicate with the directive @em{table pred/n.}".

%%%% table_predicate(add_to_query).
table_predicate(Goal) :-
	Goal =.. [Name|Args],
	length(Args,La),
	pr_table_predicate(Name/La).
table_predicate(not(Goal)) :-
	Goal =.. [Name|Args],
	length(Args,La),
	pr_table_predicate(Name/La).
shown_predicate(Goal) :-
	Goal \= not(_),
	predicate(Goal).

:- pred my_copy_term(Var, Term, NewVar, NewTerm) #"Its behaviour is
similar to @pred{copy_term/2}. It returns in @var{NewTerm} a copy of
the term @var{Term} but it only replaces with a fresh variable
@var{NewVar} the occurrences of @var{Var}".

%! my_copy_term(Var, Term, NewVar, NewTerm)
my_copy_term(Var, V, NewVar, NewVar) :- var(V), V == Var, !.
my_copy_term(Var, V, _,V) :- var(V), V \== Var, !.
my_copy_term(_, G, _,G) :- ground(G), !.
my_copy_term(Var, Struct, NewVar, NewStruct) :-
	Struct =.. [Name | Args], !,
	my_copy_list(Var, Args, NewVar, NewArgs),
	NewStruct =.. [Name | NewArgs].

my_copy_list(_,[],_,[]).
my_copy_list(Var,[T|Ts],NewVar,[NewT|NewTs]) :-
	my_copy_term(Var, T, NewVar,NewT),
	my_copy_list(Var, Ts, NewVar,NewTs).



% :- use_package(attr).
% %% Attributes predicates %%
% :- multifile attr_unify_hook/2, attribute_goals/3, attr_portray_hook/2.
% attr_unify_hook(rules(Att), B) :- get_attr_local(B, rules(AttB)), Att = AttB.
% attr_unify_hook(neg(A), B) :- not_unify(B,A).
% attribute_goals(X) --> [X ~> G], {get_attr_local(X, rules(G))}.
% attribute_goals(X) --> [X .\=. G], {get_attr_local(X, neg(G))}.
% attr_portray_hook(rules(Att), A) :- format(" ~w  .is ~w ", [A, Att]).
% attr_portray_hook(neg(Att),   A) :- format(" ~w  .\\=. ~w ", [A, Att]).
% %% Attributes predicates %%
