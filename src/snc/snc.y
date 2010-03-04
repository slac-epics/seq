%{
/**************************************************************************
			GTA PROJECT   AT division
	Copyright, 1990, The Regents of the University of California.
		         Los Alamos National Laboratory
	snc.y,v 1.2 1995/06/27 15:26:07 wright Exp
	ENVIRONMENT: UNIX
	HISTORY:
20nov91,ajk	Added new "option" statement.
08nov93,ajk	Implemented additional declarations (see VC_CLASS in parse.h).
08nov93,ajk	Implemented assignment of array elements to pv's.
02may93,ajk	Removed "parameter" definition for functions, and added "%prec"
		qualifications to some "expr" definitions.
31may94,ajk	Changed method for handling global C code.
20jul95,ajk	Added "unsigned" types (see UNSIGNED token).
11jul96,ajk	Added character constants (CHAR_CONST).
08aug96,wfl	Added new "syncQ" statement.
23jun97,wfl	Permitted pre-processor "#" lines between states. 
13jan98,wfl     Added "down a level" handling of compound expressions
09jun98,wfl     Permitted pre-processor "#" lines between state-sets
07sep99,wfl	Supported ternary operator;
		Supported local declarations (not yet finished).
22sep99,grw     Supported entry and exit actions; supported state options.
18feb00,wfl     More partial support for local declarations (still not done).
31mar00,wfl	Supported entry handler; made 'to' consistently optional.
***************************************************************************/
/*	SNC - State Notation Compiler.
 *	The general structure of a state program is:
 *		program-name
 *		declarations
 *		ss  { state { event { action ...} new-state } ... } ...
 *
 *	The following yacc definitions call the various parsing routines, which
 *	are coded in the file "parse.c".  Their major action is to build
 *	a structure for each SNL component (state, event, action, etc.) and
 *	build linked lists from these structures.  The linked lists have a
 *	hierarchical structure corresponding to the SNL block structure.
 *	For instance, a "state" structure is linked to a chain of "event",
 *	structures, which are, in turn, linked to a chain of "action"
 *	structures.
 *	The lexical analyser (see snc_lex.l) reads the input
 *	stream and passes tokens to the yacc-generated code.  The snc_lex
 *	and parsing routines may also pass data elements that take on one
 *	of the types defined under the %union definition.
 *
 */
#include	<stdio.h>
#include	<ctype.h>
#include	"parse.h"
#include	"snc_main.h"

#ifndef	TRUE
#define	TRUE	1
#define	FALSE	0
#endif

static void pp_code(char *line, char *fname);
%}

%start	state_program

%union
{
	int	ival;
	char	*pchar;
	void	*pval;
	Expr	*pexpr;
}
%token	<pchar>	STATE ENTRY STATE_SET
%token	<pchar>	NUMBER NAME
%token	<pchar>	CHAR_CONST
%token	<pchar>	DEBUG_PRINT
%token	PROGRAM ENTRY EXIT L_OPTION
%token	R_SQ_BRACKET L_SQ_BRACKET
%token	BAD_CHAR L_BRACKET R_BRACKET
%token	QUESTION COLON SEMI_COLON EQUAL
%token	L_PAREN R_PAREN PERIOD POINTER COMMA OR AND
%token	MONITOR ASSIGN TO WHEN
%token	UNSIGNED CHAR SHORT INT LONG FLOAT DOUBLE STRING_DECL
%token	EVFLAG SYNC SYNCQ
%token	ASTERISK AMPERSAND
%token	AUTO_INCR AUTO_DECR
%token	PLUS MINUS SLASH GT GE EQ LE LT NE NOT BIT_OR BIT_XOR BIT_AND
%token	L_SHIFT R_SHIFT COMPLEMENT MODULO OPTION
%token	PLUS_EQUAL MINUS_EQUAL MULT_EQUAL DIV_EQUAL AND_EQUAL OR_EQUAL
%token	MODULO_EQUAL LEFT_EQUAL RIGHT_EQUAL CMPL_EQUAL
%token	<pchar>	STRING
%token	<pchar>	C_STMT
%token	IF ELSE WHILE FOR BREAK
%token	PP_SYMBOL CR
%type	<ival>	type
%type	<pchar>	program_name program_param
%type	<pchar>	subscript
%type	<pchar>	binop asgnop unop
%type	<pexpr> global_entry_code global_exit_code
%type	<pexpr> optional_global_c global_c definitions defn_stmt defn_c_stmt
%type	<pexpr> assign_stmt monitor_stmt decl_stmt sync_stmt syncq_stmt
%type	<pexpr> optional_subscript optional_number
%type	<pexpr> state_set_list state_set state_list state
%type	<pexpr> transition_list transition state_option_value
%type	<pexpr> expr compound_expr assign_list bracked_expr
%type	<pexpr> statement stmt_list compound_stmt if_stmt else_stmt while_stmt
%type	<pexpr> for_stmt escaped_c_list local_decl_stmt
%type	<pexpr> state_option_list state_option
%type	<pexpr> condition_list
%type	<pexpr> entry_list exit_list entry exit
/* precedence rules for expr evaluation */

%right	EQUAL COMMA
%left	QUESTION COLON	/* ### check this is correct */
%left	OR AND
%left	GT GE EQ NE LE LT
%left	PLUS MINUS
%left	ASTERISK SLASH
%left	NOT UOP	/* unary operators: e.g. -x */
%left	SUBSCRIPT

%%	/* Begin rules */

state_program 	/* define a state program */
:	optional_pp_codes	/* $1 */
	program_name		/* $2 */
	program_param		/* $3 */
	definitions		/* $4 */
	global_entry_code	/* $5 */
	state_set_list		/* $6 */
	global_exit_code	/* $7 */
	optional_pp_codes	/* $8 */
	optional_global_c	/* $9 */
{
	program($2,$3,$4,$5,$6,$7,$9);
}
;

program_name 	/* program name */
:	PROGRAM NAME			{ $$ = $2; }
;

program_param
:					{ $$ = ""; }
|	L_PAREN STRING R_PAREN		{ $$ = $2; }

definitions 	/* definitions block */
:	defn_stmt			{ $$ = $1; }
|	definitions defn_stmt		{ $$ = link_expr($1, $2); }
;

defn_stmt	/* individual definitions for SNL (preceeds state sets) */
:	assign_stmt			{ $$ = $1; }
|	monitor_stmt			{ $$ = $1; }
|	decl_stmt			{ $$ = $1; }
|	sync_stmt			{ $$ = $1; }
|	syncq_stmt			{ $$ = $1; }
|	option_stmt			{ $$ = 0; }
|	defn_c_stmt			{ $$ = $1; }
|	pp_code				{ $$ = 0; }
|	error { snc_err("definitions/declarations"); }
;

assign_stmt	/* assign <var name> to <db name>; */
:	ASSIGN NAME to STRING SEMI_COLON
{
	$$ = expression(E_ASSIGN, $2, 0, expression(E_STRING, $4, 0, 0));
	/* assign_single($2, $4); */
}
|	ASSIGN NAME to subscript STRING SEMI_COLON
{		/* assign <var name>[<n>] [to] <db name>; */
	$$ = expression(E_ASSIGN, $2,
			expression(E_CONST, $4, 0, 0),
			expression(E_STRING, $5, 0, 0));
	/* assign_single($2, $4); */
}
		/* assign <var name> [to] {<db name>, ... }; */
|	ASSIGN NAME to L_BRACKET assign_list R_BRACKET SEMI_COLON
{
	$$ = expression(E_ASSIGN, $2, 0, $5);
	/* assign_list($2, $5); */
}
;

assign_list	/* {"<db name>", .... } */ 
:	STRING				{ $$ = expression(E_STRING, $1, 0, 0); }
|	assign_list COMMA STRING
			{ $$ = link_expr($1, expression(E_STRING, $3, 0, 0)); }
;

to		/* "to" */
:	/* optional */
|	TO;
;

monitor_stmt	/* variable to be monitored; delta is optional */
:	MONITOR NAME optional_subscript SEMI_COLON
{
	$$ = expression(E_MONITOR, $2, 0, $3);
	/* monitor_stmt($2, $3); */
}
;

optional_subscript
:					{ $$ = 0; }
|	subscript			{ $$ = expression(E_CONST, $1, 0, 0); }
;

subscript	/* e.g. [10] */
:	L_SQ_BRACKET NUMBER R_SQ_BRACKET	{ $$ = $2; }
;

decl_stmt	/* variable declarations (e.g. float x[20];)
		 * declaration(type, class, name, <1-st dim>, <2-nd dim>, value) */
:	type NAME SEMI_COLON
		{ $$ = declaration($1, VC_SIMPLE,  $2,  NULL, NULL, NULL); }

|	type NAME EQUAL NUMBER SEMI_COLON
		{ $$ = declaration($1, VC_SIMPLE,  $2,  NULL, NULL, $4  ); }

|	type NAME subscript SEMI_COLON
		{ $$ = declaration($1, VC_ARRAY1,  $2,  $3,   NULL, NULL); }

|	type NAME subscript subscript SEMI_COLON
		{ $$ = declaration($1, VC_ARRAY2,  $2,  $3,   $4,   NULL); }

|	type ASTERISK NAME SEMI_COLON
		{ $$ = declaration($1, VC_POINTER, $3,  NULL, NULL, NULL); }

|	type ASTERISK NAME subscript SEMI_COLON
		{ $$ = declaration($1, VC_ARRAYP,  $3,  $4,   NULL, NULL); }
;

local_decl_stmt	/* local variable declarations (not yet arrays... but easy
		   to add); not added to SNC's tables; treated as though
		   in escaped C code */
		/* ### this is not working yet; don't use it */
:	type NAME SEMI_COLON
		{ $$ = expression(E_TEXT, $2, 0, 0); }
|	type NAME EQUAL NUMBER SEMI_COLON
		{ $$ = expression(E_TEXT, $2, expression(E_CONST, $4, 0, 0), 0); }
;

type		/* types for variables defined in SNL */
:	CHAR		{ $$ = V_CHAR; }
|	SHORT		{ $$ = V_SHORT; }
|	INT		{ $$ = V_INT; }
|	LONG		{ $$ = V_LONG; }
|	UNSIGNED CHAR	{ $$ = V_UCHAR; }
|	UNSIGNED SHORT	{ $$ = V_USHORT; }
|	UNSIGNED INT	{ $$ = V_UINT; }
|	UNSIGNED LONG	{ $$ = V_ULONG; }
|	FLOAT		{ $$ = V_FLOAT; }
|	DOUBLE		{ $$ = V_DOUBLE; }
|	STRING_DECL	{ $$ = V_STRING; }
|	EVFLAG		{ $$ = V_EVFLAG; }
|	error { snc_err("type specifier"); }
;

sync_stmt	/* sync <variable> <event flag> */
:	SYNC NAME optional_subscript to NAME SEMI_COLON
{
	$$ = expression(E_SYNC, $2, $3, expression(E_X, $5, 0, 0));
	/* sync_stmt($2, $3, $5); */
}
;

syncq_stmt	/* syncQ <variable> [[subscript]] to <event flag> [<max queue size>] */
:	SYNCQ NAME optional_subscript to NAME SEMI_COLON
{
	$$ = expression(E_SYNCQ, $2, $3, expression(E_X, $5, 0, 0));
	/* syncq_stmt($2, $3, $5, NULL); */
}
|	SYNCQ NAME optional_subscript to NAME optional_number SEMI_COLON
{
	$$ = expression(E_SYNCQ, $2, $3, expression(E_X, $5, $6, 0));
	/* syncq_stmt($2, $3, $5, $6); */
}
;

optional_number
:				{ $$ = 0; }
|	NUMBER			{ $$ = expression(E_CONST, $1, 0, 0); }
;

defn_c_stmt	/* escaped C in definitions */
:	escaped_c_list		{ $$ = $1; }
;

option_stmt	/* option +/-<option>;  e.g. option +a; */
:	OPTION PLUS NAME SEMI_COLON	{ option_stmt($3, TRUE); }
|	OPTION MINUS NAME SEMI_COLON	{ option_stmt($3, FALSE); }
;

global_entry_code
:						{ $$ = 0; }
|	ENTRY L_BRACKET stmt_list R_BRACKET	{ $$ = $3; }
;

global_exit_code
:						{ $$ = 0; }
|	EXIT L_BRACKET stmt_list R_BRACKET	{ $$ = $3; }
;

state_set_list 	/* a program body is one or more state sets */
:	state_set			{ $$ = $1; }
|	state_set_list state_set	{ $$ = link_expr($1, $2); }
;

state_set 	/* define a state set */
:	STATE_SET NAME L_BRACKET state_list R_BRACKET
					{ $$ = expression(E_SS, $2, $4, 0); }
|	pp_code				{ $$ = 0; }
|	error				{ snc_err("state set"); }
;

state_list /* define a state set body (one or more states) */
:	state				{ $$ = $1; }
|	state_list state		{ $$ = link_expr($1, $2); }
|	error				{ snc_err("state list"); }
;

state	/* a block that defines a single state */
: 	STATE NAME L_BRACKET state_option_list condition_list R_BRACKET
			{ $$ = expression(E_STATE, $2, $5, $4); }
|	pp_code				{ $$ = 0; }
|	error				{ snc_err("state block"); }
;

state_option_list /* A list of options for a single state */
:	/* Optional */			{ $$ = NULL; }
|	state_option			{ $$ = $1; }
|	state_option_list state_option	{ $$ = link_expr($1, $2); }
|	error				{ snc_err("state option list"); }
;

state_option /* An option for a state */
:	OPTION state_option_value NAME SEMI_COLON
		{ $$ = expression(E_OPTION,$3,$2,0); }
		/* $$ = expression(E_OPTION,"stateoption",$3,"+"); */
		/* $$ = expression(E_OPTION,"stateoption",$3,"-"); */
|	error	{ snc_err("state option specifier"); }
;

state_option_value
:	PLUS	{ $$ = expression(E_X, "+", 0, 0); }
|	MINUS	{ $$ = expression(E_X, "-", 0, 0); }

condition_list /* Conditions and resulting actions */
:	entry_list transition_list exit_list
				{ $$ = link_expr( link_expr($1,$2), $3 ); }
|	error			{ snc_err("state condition list"); }
;

entry_list
:	/* optional */		{ $$ = NULL; }
|	entry			{ $$ = $1; }
|	entry_list entry	{ $$ = link_expr( $1, $2 ); }
;

exit_list
:	/* optional */		{ $$ = NULL; }
|	exit			{ $$ = $1; }
|	exit_list exit		{ $$ = link_expr( $1, $2 ); }
;

entry	/* On entry to a state, do this */
:	ENTRY L_BRACKET stmt_list R_BRACKET
				{ $$ = expression( E_ENTRY, "entry", 0, $3 ); } 
|	error			{ snc_err("entry block"); }
;

exit	/* On exit from a state, do this */
:	EXIT L_BRACKET stmt_list R_BRACKET
				{ $$ = expression( E_EXIT, "exit", 0, $3 ); } 
|	error			{ snc_err("exit block"); }
;

transition_list	/* all transitions for one state */
:	transition			{ $$ = $1; }
|	transition_list transition	{ $$ = link_expr($1, $2); }
|	error				{ snc_err("when transition list"); }
;

transition /* define a transition condition and action */
:	WHEN L_PAREN expr R_PAREN L_BRACKET stmt_list R_BRACKET STATE NAME
					{ $$ = expression(E_WHEN, $9, $3, $6); }
|	local_decl_stmt			{ $$ = $1; }
|	pp_code				{ $$ = 0; }
|	error				{ snc_err("when transition block"); }
;

expr	/* general expr: e.g. (-b+2*a/(c+d)) != 0 || (func1(x,y) < 5.0) */
	/* Expr *expression(int type, char *value, Expr *left, Expr *right) */
:	compound_expr			{ $$ = expression(E_COMMA, "", $1, 0); }
|	expr binop expr %prec UOP	{ $$ = expression(E_BINOP, $2, $1, $3); }
|	expr asgnop expr		{ $$ = expression(E_ASGNOP, $2, $1, $3); }
|	unop expr  %prec UOP		{ $$ = expression(E_UNOP, $1, $2, 0); }
|	AUTO_INCR expr  %prec UOP	{ $$ = expression(E_PRE, "++", $2, 0); }
|	AUTO_DECR expr  %prec UOP	{ $$ = expression(E_PRE, "--", $2, 0); }
|	expr AUTO_INCR  %prec UOP	{ $$ = expression(E_POST, "++", $1, 0); }
|	expr AUTO_DECR  %prec UOP	{ $$ = expression(E_POST, "--", $1, 0); }
|	NUMBER				{ $$ = expression(E_CONST, $1, 0, 0); }
|	CHAR_CONST			{ $$ = expression(E_CONST, $1, 0, 0); }
|	STRING				{ $$ = expression(E_STRING, $1, 0, 0); }
|	NAME				{ $$ = expression(E_VAR, $1, 0, 0); }
|	NAME L_PAREN expr R_PAREN	{ $$ = expression(E_FUNC, $1, $3, 0); }
|	EXIT L_PAREN expr R_PAREN	{ $$ = expression(E_FUNC, "exit", $3, 0); }
|	L_PAREN expr R_PAREN		{ $$ = expression(E_PAREN, "", $2, 0); }
|	expr bracked_expr %prec SUBSCRIPT { $$ = expression(E_SUBSCR, "", $1, $2); }
|	/* empty */			{ $$ = 0; }
;

compound_expr
:	expr COMMA expr			{ $$ = link_expr($1, $3); }
|	compound_expr COMMA expr	{ $$ = link_expr($1, $3); }
;

bracked_expr	/* e.g. [k-1] */
:	L_SQ_BRACKET expr R_SQ_BRACKET	{ $$ = $2; }
;

unop	/* Unary operators */
:	PLUS		{ $$ = "+"; }
|	MINUS		{ $$ = "-"; }
|	ASTERISK	{ $$ = "*"; }
|	AMPERSAND	{ $$ = "&"; }
|	NOT		{ $$ = "!"; }
|	COMPLEMENT	{ $$ = "~"; }
;

binop	/* Binary operators */
:	MINUS		{ $$ = "-"; }
|	PLUS		{ $$ = "+"; }
|	ASTERISK	{ $$ = "*"; }
|	SLASH 		{ $$ = "/"; }
|	GT		{ $$ = ">"; }
|	GE		{ $$ = ">="; }
|	EQ		{ $$ = "=="; }
|	NE		{ $$ = "!="; }
|	LE		{ $$ = "<="; }
|	LT		{ $$ = "<"; }
|	OR		{ $$ = "||"; }
|	AND		{ $$ = "&&"; }
|	L_SHIFT		{ $$ = "<<"; }
|	R_SHIFT		{ $$ = ">>"; }
|	BIT_OR		{ $$ = "|"; }
|	BIT_XOR		{ $$ = "^"; }
|	BIT_AND		{ $$ = "&"; }
|	MODULO		{ $$ = "%"; }
|	QUESTION	{ $$ = "?"; }	/* fudges ternary operator */
|	COLON		{ $$ = ":"; }	/* fudges ternary operator */
|	PERIOD		{ $$ = "."; }	/* fudges structure elements */
|	POINTER		{ $$ = "->"; }	/* fudges ptr to structure elements */
;

asgnop	/* Assignment operators */
:	EQUAL		{ $$ = "="; }
|	PLUS_EQUAL	{ $$ = "+="; }
|	MINUS_EQUAL	{ $$ = "-="; }
|	AND_EQUAL	{ $$ = "&="; }
|	OR_EQUAL	{ $$ = "|="; }
|	DIV_EQUAL	{ $$ = "/="; }
|	MULT_EQUAL	{ $$ = "*="; }
|	MODULO_EQUAL	{ $$ = "%="; }
|	LEFT_EQUAL	{ $$ = "<<="; }
|	RIGHT_EQUAL	{ $$ = ">>="; }
|	CMPL_EQUAL	{ $$ = "^="; }
;

compound_stmt		/* compound statement e.g. { ...; ...; ...; } */
:	L_BRACKET stmt_list R_BRACKET { $$ = expression(E_CMPND, "",$2, 0); }
|	error { snc_err("action statements"); }	
;

stmt_list
:	statement		{ $$ = $1; }
|	stmt_list statement	{ $$ = link_expr($1, $2); }
|	/* empty */		{ $$ = 0; }
;

statement
:	compound_stmt			{ $$ = $1; }
|	expr SEMI_COLON			{ $$ = expression(E_STMT, "", $1, 0); }
|	BREAK SEMI_COLON		{ $$ = expression(E_BREAK, "", 0, 0); }
|	if_stmt				{ $$ = $1; }
|	else_stmt			{ $$ = $1; }
|	while_stmt			{ $$ = $1; }
|	for_stmt			{ $$ = $1; }
|	C_STMT				{ $$ = expression(E_TEXT, $1, 0, 0); }
|	pp_code				{ $$ = 0; }
/* |	error 				{ snc_err("action statement"); } */
;

if_stmt
:	IF L_PAREN expr R_PAREN statement { $$ = expression(E_IF, "", $3, $5); }
;

else_stmt
:	ELSE statement			{ $$ = expression(E_ELSE, "", $2, 0); }
;

while_stmt
:	WHILE L_PAREN expr R_PAREN statement { $$ = expression(E_WHILE, "", $3, $5); }
;

for_stmt
:	FOR L_PAREN expr SEMI_COLON expr SEMI_COLON expr R_PAREN statement
	{ $$ = expression(E_FOR, "", expression(E_X, "", $3, $5),
				expression(E_X, "", $7, $9) ); }
;

pp_code		/* pre-processor code (e.g. # 1 "test.st") */
:	PP_SYMBOL NUMBER STRING CR	{ pp_code($2, $3); }
|	PP_SYMBOL NUMBER CR		{ pp_code($2, 0); }
|	PP_SYMBOL STRING CR		{ /* Silently consume #pragma lines */ }
;

optional_pp_codes
:	/* optional */
|	pp_codes

pp_codes	/* one or more pp_code */
:	pp_code
|	pp_codes pp_code
;

optional_global_c
:	/* optional */		{ $$ = 0; }
|	global_c		{ $$ = $1; }

global_c
:	escaped_c_list		{ $$ = $1; }
;

escaped_c_list
:	C_STMT			{ $$ = expression(E_TEXT, $1, 0, 0); }
|	escaped_c_list C_STMT	{ $$ = link_expr($1, expression(E_TEXT, $2, 0, 0)); }
;
%%
#include	"snc_lex.c"

static int yyparse (void);

/* yyparse() is static, so we create global access to it */
void compile (void)
{
	yyparse ();
}

/* Interpret pre-processor code */
static void pp_code(char *line, char *fname)
{
	globals->line_num = atoi(line);
	if (fname != 0)
	globals->src_file = fname;
}
