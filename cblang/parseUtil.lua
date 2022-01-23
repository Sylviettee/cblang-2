--[[
MIT License

Copyright (c) 2021 Eduardo Bart (https://github.com/edubart)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

-- I didn't feel like writing a Lua parser

local skip = [[
SKIP          <-- (%sp+ / COMMENT)*
COMMENT       <-- `//` (!%nl .)* %nl
]]

local statement = [==[
Statement     <-- Label / Return / Break / Goto / Do / While / Repeat / If / ForNum / ForIn
                  / VarDecl / Assign / (call @`;`)
Block         <== Statement*

Label         <== `::` @NAME @`::`
Return        <== `return` exprlist? @`;`
Break         <== `break` @`;`
Goto          <== `goto` @NAME @`;`
Do            <== `{` Block @`}`
While         <== `while` @`(` @expr @`)` @`{` Block @`}`
Repeat        <== `do` `{` Block `}` @`while` @`(` @expr @`)`
If            <== `if` @`(` @expr @`)` @`{` Block @`}`
                  {| (`else` `if` `(` @expr @`)` @`{` Block @`}`)* |}
                  (`else` @`{` Block @`}`)?
ForNum        <== `for` @`(` Id `=` @expr @`,` @expr (`,` @expr)? `)` @`{` Block @`}`
ForIn         <== `for` @`(` @idlist `in` @exprlist @`)` @`{` Block @`}`
VarDecl       <== `local` iddecllist (`=` @exprlist)? @`;`
Assign        <== varlist {ASSIGN_OP}? `=` @exprlist  @`;`

Number        <== NUMBER->tonumber SKIP
String        <== STRING SKIP
Boolean       <== `false`->tofalse / `true`->totrue
Nil           <== `nil`
Varargs       <== `...`
Id            <== NAME
IdDecl        <== NAME (`<` @NAME @`>`)?
Function      <== `function` funcbody
Table         <== `{` (field (fieldsep field)* fieldsep?)? @`}` / `[` (expr (fieldsep expr)*)? `]`
Paren         <== `(` @expr @`)`

Pair          <== `[` @expr @`]` @`=` @expr / NAME `=` @expr
Call          <== callargs
CallMethod    <== `:` @NAME @callargs
DotIndex      <== `.` @NAME
ColonIndex    <== `:` @NAME
KeyIndex      <== `[` @expr @`]`
indexsuffix   <-- DotIndex / KeyIndex
callsuffix    <-- Call / CallMethod
var           <-- (exprprimary (callsuffix+ indexsuffix / indexsuffix)+)~>rfoldright / Id
call          <-- (exprprimary (indexsuffix+ callsuffix / callsuffix)+)~>rfoldright
exprsuffixed  <-- (exprprimary (indexsuffix / callsuffix)*)~>rfoldright
funcbody      <-- @`(` funcargs @`)` @`{` Block @`}`
field         <-- Pair / expr
fieldsep      <-- `,` / `;`
callargs      <-| `(` (expr (`,` @expr)*)? @`)` / Table / String
idlist        <-| Id (`,` @Id)*
iddecllist    <-| IdDecl (`,` @IdDecl)*
funcargs      <-| (Id (`,` Id)* (`,` Varargs)? / Varargs)?
exprlist      <-| expr (`,` @expr)*
varlist       <-| var (`,` @var)*

opor     :BinaryOp <== `or`->'or' @exprand
opand    :BinaryOp <== `and`->'and' @exprcmp
opcmp    :BinaryOp <== (`==`->'==' / `~=`->'~=' / `<=`->'<=' / `>=`->'>=' / `<`->'<' / `>`->'>') @exprbor
opbor    :BinaryOp <== `|`->'|' @exprbxor
opbxor   :BinaryOp <== `~`->'~' @exprband
opband   :BinaryOp <== `&`->'&' @exprbshift
opbshift :BinaryOp <== (`<<`->'<<' / `>>`->'>>') @exprconcat
opconcat :BinaryOp <== `..`->'..' @exprconcat
oparit   :BinaryOp <== (`+`->'+' / `-`->'-') @exprfact
opfact   :BinaryOp <== (`*`->'*' / `%/`->'//' / `/`->'/' / `%`->'%') @exprunary
oppow    :BinaryOp <== `^`->'^' @exprunary
opunary  :UnaryOp  <== (`not`->'not' / `#`->'#' / `-`->'-' / `~`->'~') @exprunary

expr          <-- expror
expror        <-- (exprand opor*)~>foldleft
exprand       <-- (exprcmp opand*)~>foldleft
exprcmp       <-- (exprbor opcmp*)~>foldleft
exprbor       <-- (exprbxor opbor*)~>foldleft
exprbxor      <-- (exprband opbxor*)~>foldleft
exprband      <-- (exprbshift opband*)~>foldleft
exprbshift    <-- (exprconcat opbshift*)~>foldleft
exprconcat    <-- (exprarit opconcat*)~>foldleft
exprarit      <-- (exprfact oparit*)~>foldleft
exprfact      <-- (exprunary opfact*)~>foldleft
exprunary     <-- opunary / exprpow
exprpow       <-- (exprsimple oppow*)~>foldleft
exprsimple    <-- Nil / Boolean / Number / String / Varargs / Function / Table / exprsuffixed
exprprimary   <-- Id / Paren

STRING        <-- STRING_SHRT / STRING_LONG
STRING_LONG   <-- {:LONG_OPEN {LONG_CONTENT} @LONG_CLOSE:}
STRING_SHRT   <-- {:QUOTE_OPEN {~QUOTE_CONTENT~} @QUOTE_CLOSE:}

QUOTE_OPEN    <-- {:qe: ['"] :}
QUOTE_CONTENT <-- (ESCAPE_SEQ / !(QUOTE_CLOSE / LINEBREAK) .)*
QUOTE_CLOSE   <-- =qe

ESCAPE_SEQ    <-- '\' @ESCAPE
ESCAPE        <-- [\'"ntrabvf] /
                  ('x' {HEX_DIGIT^2}) /
                  ('u' '{' {HEX_DIGIT^+1} '}') /
                  ('z' SPACE*) /
                  (DEC_DIGIT DEC_DIGIT^-1 !DEC_DIGIT / [012] DEC_DIGIT^2) /
                  (LINEBREAK $10)

NUMBER        <-- {HEX_NUMBER / DEC_NUMBER}
HEX_NUMBER    <-- '0' [xX] @HEX_PREFIX ([pP] @EXP_DIGITS)?
DEC_NUMBER    <-- DEC_PREFIX ([eE] @EXP_DIGITS)?
HEX_PREFIX    <-- HEX_DIGIT+ ('.' HEX_DIGIT*)? / '.' HEX_DIGIT+
DEC_PREFIX    <-- DEC_DIGIT+ ('.' DEC_DIGIT*)? / '.' DEC_DIGIT+
EXP_DIGITS    <-- [+-]? DEC_DIGIT+

LONG_CONTENT  <-- (!LONG_CLOSE .)*
LONG_OPEN     <-- '[' {:eq: '='*:} '[' LINEBREAK?
LONG_CLOSE    <-- ']' =eq ']'

ASSIGN_OP     <-- '+' / '-' / '*' / '//' / '/' / '%' / '^' /
                  '|' / '~' / '&' / '<<' / '>>' / '..' /
                  'and' / 'or'

NAME          <-- (!KEYWORD)^Expected_Id (!'__M')^Expected_NoMangle {NAME_PREFIX NAME_SUFFIX?} SKIP
NAME_PREFIX   <-- [_a-zA-Z]
NAME_SUFFIX   <-- [_a-zA-Z0-9]+

SKIP          <-- %Skip

SPACE         <-- %sp
LINEBREAK     <-- %cn %cr / %cr %cn / %cn / %cr

HEX_DIGIT     <-- [0-9a-fA-F]
DEC_DIGIT     <-- [0-9]

EXTRA_TOKENS  <-- `[[` `[=` -- unused rule, here just to force defining these tokens
]==]

local rex = require 'lpegrex'

skip = rex.compile(skip)
statement = rex.compile(statement, { Skip = skip })

return {
   skip = skip,
   statement = statement,
}
