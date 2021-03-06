:- module(scasp_io, [
	load_program/1,
	write_program/0,
	process_query/2,
	ask_for_more_models/0,
	allways_ask_for_more_models/0,
	init_counter/0,
	increase_counter/0,
	print_output/1,
	print_model/1,
	print_check_calls_calling/2,
	if_user_option/2,
	set/2,
	parse_args/3,
	current_option/2,
	counter/2,
	set_options/1,
	answer_counter/1
	]).


%% ------------------------------------------------------------- %%
:- use_package(assertions).
:- doc(title, "Module for input / output predicates").
:- doc(author, "Joaquin Arias").
:- doc(filetype, module).

:- doc(module, "

This module contains the code used to load, parser, translate and
print the program and results of the evaluation. It uses the
implementation of s(ASP) by @em{Marple} ported to CIAO by @em{Joaquin
Arias} in the folder @file{./src/sasp/}.

").

%% ------------------------------------------------------------- %%

:- use_module('sasp/output').
:- reexport('sasp/output', [
	pr_rule/2,
	pr_query/1,
	pr_user_predicate/1,
	pr_table_predicate/1
			    ]).
:- use_module('sasp/main').

%% ------------------------------------------------------------- %%

:- pred load_program(Files) : list(Files) #"Call s(ASP) to generate
and assert the translation of the progam (with dual and nmr_check)".

:- dynamic loaded_file/1.
load_program(X) :-
	retractall(loaded_file(_)),
	(
	    list(X) ->
	    Files = X
	;
	    Files = [X]
	),
	main(['-g'| Files]),
	assert(loaded_file(Files)).

:- pred write_program/0 #"Call c(asp) to print the source code of the
translation of the programs already loaded by @pred(load_program/1)".

write_program :-
	loaded_file(Files),
	main(['-d0'|Files]).

:- dynamic cont/0.

:- pred process_query(Q, Query) #"Initialize internal flags to allows
the generation of multiples models in the interaction and top-level
mode (even when the query is ground). Returns in @var{Query} a list
with the sub_goals in @var{Q} and @em{add_to_query} with run the
nmr_check".

process_query(A,Query) :-
	(
	    list(A) -> As = A ; As = [A]
	),
	retractall(cont),
	(
	    ground(As) -> assert(cont) ; true
	),
	append(As, [add_to_query], Query).

:- pred ask_for_more_models/0 #"Ask if the user want to generate more
models (interactive and top-level mode)".

ask_for_more_models :-
	(
	    cont, print('next ? '), get_char(R),true, R \= '\n' ->
	    get_char(_),
	    fail
	;
	    true
	).

:- pred ask_for_more_models/0 #"Ask if the user want to generate more
models (execution from console)".

allways_ask_for_more_models :-
	(
	    print(' ? '), get_char(R),true, R \= '\n' ->
	    get_char(_),
	    nl,
	    fail
	;
	    true
	).

:- pred init_counter/0 #"Reset the value of answer_counter to 0".

:- dynamic answer_counter/1.
init_counter :-
	retractall(answer_counter(_)),
	assert(answer_counter(0)).

:- pred increase_counter/0 #"Add 1 to the current value of
answer_counter".

increase_counter :-
	answer_counter(N),
	N1 is N + 1,
	retractall(answer_counter(N)),
	assert(answer_counter(N1)).

:- pred print_output(StackOut) #"Print the justification tree using
@var{StackOut}, the final call stack".

%% Print output predicates to presaent the results of the query
print_output(StackOut) :-
	print_stack(StackOut), nl,
	true.

:- pred print_model(Model) #"Print the partial model of the program
using @var{Model}".

%% The model is obtained from the justification tree.
print_model([F|J]) :-
	nl,
	print('{ '),
	print(F),
	print_model_(J),
	print(' }'), nl.

print_model_([]) :- !.
print_model_([X|Xs]) :-
	print_model_(X), !,
	print_model_(Xs).
print_model_([X]) :- !,
	( X \= proved(_) ->
	  print(X)
	; true
	).
print_model_([X, Y|Xs]) :-
	( X \= proved(_) ->
	  print(' , '),
	  print(X)
	; true
	),
	print_model_([Y|Xs]).


print_j(Justification,I) :-
	print_model(Justification),
	nl,
	print_j_(Justification,I).
print_j_([],_).
print_j_([A,[]],I):- !,
	tab(I), print(A), print('.'), nl.
print_j_([A,[]|B],I):- !,
	tab(I), print(A), print(','), nl,
	print_j_(B,I).
print_j_([A,ProofA|B],I):-
	tab(I), print(A), print(' :-'), nl,
	I1 is I + 4, print_j_(ProofA,I1),
	print_j_(B,I).

%% The stack is generated adding the last calls in the head (to avoid
%% the use of append/3). To print the stack, it is reversed.

%% NOTE that a model could be generated during the search with some
%% calls in the stack which are not present in the model (e.g. the
%% model of path(1,4) for the path/2 program - more details in the
%% file README)
print_stack(Stack) :-
	reverse(Stack, RStack),
	nl,
	print_s(RStack).
	% print('{ '),
	% print(RStack),
	% print(' }'), nl.




%% Initial interpreters...
query2([]).
query2([X|Xs]) :-
	query2(Xs),
	query2(X).
query2(X) :-
	pr_rule(X, Body),
	query2(Body).


%:- table query3/3.
query3([X|Xs], I, O) :-
	format('Calling ~w \t with stack = ~w', [X, I]), nl,
	query3(X,  [X|I], O1),
	query3(Xs, O1,    O).
query3([], I, I) :- !.
query3(X,  I, O) :-
	pr_rule(X, Body),
	query3(Body, I, O).



:- pred print_check_calls_calling(Goal, StackIn) #"Auxiliar predicate
to print @var{StackIn} the current stack and @var{Goal}. This
predicate is executed when the flag @var{check_calls} is
@em{on}. NOTE: use check_calls/0 to activate the flag".

print_check_calls_calling(Goal,I) :-
	reverse([('¿'+Goal+'?')|I],RI),
	format('\n---------------------Calling ~p-------------',[Goal]),
	print_s(RI).
print_s(Stack) :-
	print_s_(Stack,5,5).
print_s_([],_,_) :- display('.'),nl.
print_s_([[]|As],I,I0) :- !,
	I1 is I - 4,
	print_s_(As,I1,I0).
print_s_([A|As],I,I0) :- !,
	(
	    I0 > I ->
	    print('.')
	;
	    I0 < I ->
	    print(' :-')
	;
	    (
		I0 \= 5 ->
		print(',')
	    ;
		true
	    )
	),
	nl,tab(I),print(A),	
	I1 is I + 4,
	print_s_(As,I1,I).




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Set options
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- dynamic current_option/2, counter/2.

set_options(Options) :-
	set_default_options,
	set_user_options(Options).

set_default_options :-
	set(answers,-1),
	set(verbose,0).

set_user_options([]).
set_user_options([O | Os]) :-
	(
	    set_user_option(O) ->
	    set_user_options(Os)
	;
	    format('Error: the option ~w is not supported!\n\n',[O]),
	    fail
	).

set_user_option('-h') :- help.
set_user_option('-?') :- help.
set_user_option('--help') :- help.
set_user_option('-i') :- set(interactive, on).
set_user_option('--interactive') :- set(interactive, on).
set_user_option('-a').
set_user_option('--auto').
set_user_option(Option) :- atom_chars(Option,['-','s'|Ns]),number_chars(N,Ns),set(answers,N).
set_user_option(Option) :- atom_chars(Option,['-','n'|Ns]),number_chars(N,Ns),set(answers,N).
set_user_option('-v') :- set(check_calls, on).
set_user_option('--verbose') :- set(check_calls, on).
set_user_option('-j') :- set(print, on).
set_user_option('--justification') :- set(print, on).
set_user_option('-d0') :- set(write_program, on).

:- pred if_user_option(Name, Call) : (ground(Name), callable(Call))
#"If the flag @var{Name} is on them the call @var{Call} is executed".

if_user_option(Name,Call) :-
	(
	    current_option(Name,on) ->
	    call(Call)
	;
	    true
	).

:- pred set(Option, Value) #"Used to set-up the user options".

set(Option, Value) :-
	retractall(current_option(Option, _)),
	assert(current_option(Option,Value)).

help :-
        display('Usage: scasp [options] InputFile(s)\n\n'),
        display('s(CASP) computes stable models of ungrounded normal logic programs.\n'),
        display('Command-line switches are case-sensitive!\n\n'),
        display(' General Options:\n\n'),
        display('  -h, -?, --help        Print this help message and terminate.\n'),
        display('  -i, --interactive     Run in user / interactive mode.\n'),
        display('  -a, --auto            Run in automatic mode (no user interaction).\n'),
        display('  -sN, -nN              Compute N answer sets, where N >= 0. 0 for all.\n'),
        display('  -v, --verbose         Enable verbose progress messages.\n'),
        display('  -j, --justification   Print proof tree for each solution.\n'),
        display('  -d0                   Print the program translated (with duals and nmr_check).\n'),
	display('\n'),
	abort.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parse arguments
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- pred parse_args(Args, Options, Sources) #"Select from the list of
arguments in @var{Args} which are the user-options, @var{Options} and
which are the program files, @var{Sources}".

parse_args([],[],[]).
parse_args([O | Args], [O | Os], Ss) :-
	atom_concat('-',_,O),!,
	parse_args(Args, Os, Ss).
parse_args([S | Args], Os, [S | Ss]) :-
	parse_args(Args, Os, Ss).
