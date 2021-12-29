local util = require 'cblang.parseUtil'
local rex = require 'lpegrex'

local grammar = rex.compile([[
Chunk         <== SKIP Include* Class*

Include       <-- (BaseInclude / FromNative / FromNativeRef) `;`
BaseInclude   <== `include` {:path: @Path :}
FromNative    <== `from` @`native` `include` {:path: @Path :}
FromNativeRef <== `from` @`native` `reference` {:path: @Path :}
Path          <-| Ident (`.` @Ident)*

Class         <== `class` {:name: Ident :} {:args: ClassArgs? :} ClassBody
ClassArgs     <== `(` (Ident (`,` Ident)*)? `)`
ClassBody     <-- `{` FunctionCb* `}`

FunctionCb    <== (`static` {:static: $true :})? `function` {:name: @Ident :} {:args: FuncArgs :} FuncBody
FuncArgs      <== @`(` (Ident (`,` @Ident)*)? @`)`
FuncBody      <-- @`{` Statement* @`}`

Ident         <== NAME

Statement     <== %LuaStatement

NAME          <-- !KEYWORD {NAME_PREFIX NAME_SUFFIX?} SKIP
NAME_PREFIX   <-- [_a-zA-Z]
NAME_SUFFIX   <-- [_a-zA-Z0-9]+

SKIP          <-- %Skip
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
