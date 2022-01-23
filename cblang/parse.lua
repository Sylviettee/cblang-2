local util = require 'cblang.parseUtil'
local rex = require 'lpegrex'

local grammar = rex.compile([[
Chunk         <== SKIP Include* Class* !.^Expected_Eof

Include       <-- (BaseInclude / FromNative / FromNativeRef) @`;`
BaseInclude   <== `include` @Path
FromNative    <== `from` @`native` `include` @Path
FromNativeRef <== `from` @`native` @`reference` @Path
Path          <-| Id (`.` @Id)*

Class         <== `class` @Id Args? ClassBody
ClassBody     <== @`{` FunctionCb* @`}`

FunctionCb    <== ((`static` $true) / $false) `function` @Id @Args FuncBody
FuncBody      <== @`{` Statement* @`}`

Args          <== `(` (Id (`,` Id)* (`,` Varargs^Expected_NameOrVararg)? / Varargs)? @`)`

Id            <== NAME
Varargs       <== `...`

Statement     <== %LuaStatement

NAME          <-- (!KEYWORD)^Expected_Id (!'__M')^Expected_NoMangle {NAME_PREFIX NAME_SUFFIX?} SKIP
NAME_PREFIX   <-- [_a-zA-Z]
NAME_SUFFIX   <-- [_a-zA-Z0-9]+

SKIP          <-- %Skip

EXTRA_TOKENS  <-- `and` `break` `do` `else` `elseif` `end`
                  `false` `for` `function` `goto` `if` `in`
                  `local` `nil` `not` `or` `repeat` `return`
                  `then` `true` `until` `while`
]],  {
   Skip = util.skip,
   LuaStatement = util.statement
})

local function parse(s)
   local ast, err, pos = grammar:match(s)

   if not ast then
      local line, col, details = rex.calcline(s, pos)

      return nil, {
         details = details,
         line = line,
         col = col,
         tag = err,
      }
   end

   return ast
end

return parse
