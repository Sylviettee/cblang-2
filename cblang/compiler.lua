local ArraySet = require 'cblang.ArraySet'
local checks = require 'cblang.checks'
local errors = require 'cblang.errors'
local parse = require 'cblang.parse'
local rex = require 'lpegrex'

local globals

do
   local g = { const = true, used = true, kind = 'global variable' }

   local function extend(tbl, ext)
      for i, v in pairs(ext) do
         tbl[i] = v
      end

      return tbl
   end

   local dep = extend({ deprecated = true }, g)
   local compat = extend({ compat = 'always' }, g)

   globals = function(v)
      local maybeCompat = v < 5.3 and extend({ compat = 'maybe' }, g) or g

      return {
         _G = g,
         arg = g,
         getmetatable = g,
         tonumber = g,
         select = g,
         dofile = g,
         rawget = g,
         _VERSION = g,
         print = g,
         rawequal = g,
         type = g,
         collectgarbage = g,
         error = g,
         setmetatable = g,
         next = g,
         tostring = g,
         require = g,
         rawset = g,
         package = maybeCompat,
         loadfile = maybeCompat,
         pairs = maybeCompat,
         coroutine = maybeCompat,
         os = maybeCompat,
         table = maybeCompat,
         ipairs = maybeCompat,
         pcall = maybeCompat,
         xpcall = maybeCompat,
         io = maybeCompat,
         debug = maybeCompat,
         math = maybeCompat,
         load = maybeCompat,
         assert = maybeCompat,
         string = maybeCompat,
         rawlen = v < 5.2 and compat,
         utf8 = v < 5.3 and compat,
         getfenv = v == 5.1 and g or dep,
         gcinfo = v == 5.1 and g or dep,
         module = v == 5.1 and g or dep,
         unpack = v == 5.1 and g or dep,
         newproxy = v == 5.1 and g or dep,
         setfenv = v == 5.1 and g or dep,
         loadstring = v < 5.3 and g or dep,
         -- Bit32 only existed in 5.2 and emulating it entirely would be
         -- difficult to say the least
         bit32 = extend({ bit = true }, g)
      }
   end
end

---@alias ext table<any, any>

---@class artifacts
---@field imports import[]
---@field errors error[]
---@field files table<string, compiler>
---@field cache cache
---@field compat boolean
---@field bit boolean
---@field config config

---@class import
---@field rewrite string
---@field kind string
---@field name string
---@field contents? string[]
---@field path? string
---@field import boolean
---@field sym? symbol

---@class cache
---@field includedSym table<symbol, boolean>

---@class error
---@field msg string
---@field code string
---@field start integer
---@field stop integer
---@field file string

---@class config
---@field indentType 'space'|'tab'
---@field indentSize integer
---@field target number
---@field compat boolean
---@field path string

---@class variables: variable
---@field __array boolean

---@class variable: any
---@field kind string
---@field file string
---@field node baseNode
---@field const? boolean
---@field name string
---@field used? boolean
---@field rewrite? string
---@field deprecated? boolean
---@field compat? string
---@field bit? boolean

---@class baseNode: any
---@field pos integer
---@field endpos integer
---@field tag string

---@class check

---@class symbol: variable, any
---@field contents string[]
---@field depends ArraySet
---@field exported boolean
---@field hasMain boolean

---@class compiler
---@field artifacts artifacts
---@field variables table<string, variable|variable[]>
---@field source string
---@field toCheck check[]
---@field exports table<string, symbol>
---@field symbols table<string, symbol>
---@field scopes table<string, variable>[]
---@field disabledUndef boolean?
---@field isRoot? boolean
---@field file string
---@field config config
local compiler = {}

---@param file string|file*
---@param artifacts artifacts
---@return compiler
function compiler.compile(file, artifacts, isRoot, config)
   artifacts = artifacts or {
      config = config,
      imports = {},
      errors = {},
      files = {},
      cache = {
        includedSym = {}
      },
   }

   config = artifacts.config

   local source

   do
      local f

      if type(file) == 'string' then
         f = io.open(file, 'r')
      else
         f = file[2]
         file = file[1]
      end

      if not f then
         return nil, 'unable to open file ' .. file
      end

      source = f:read('*a')

      f:close()
   end

   local ast, err = parse(source)

   if not ast then
      return nil, string.format(
         '%u:%u: %s\n%s\n%s',
         err.line,
         err.col,
         errors[err.tag],
         err.details,
         string.rep(' ', err.col - 1) .. '^'
      )
   end

   local self = setmetatable({
      variables = globals(config.target),
      config = artifacts.config,
      artifacts = artifacts,
      source = source,
      isRoot = isRoot,
      toCheck = {},
      exports = {},
      symbols = {},
      scopes = {},
      file = file
   }, { __index = compiler })

   if not artifacts.files[file] then
      artifacts.files[file] = self
   end

   for i = 1, #ast do
      local node = ast[i]
      local fn = self[node.tag .. 'Prepare']

      if fn then
         fn(self, node)
      end
   end

   self:visit(ast)

   self:checkUnusedSymbols()
   self:checkCustomChecks()

   return self
end

-- Symbols

---@param name string
---@param node baseNode
---@param ext ext
function compiler:startSymbol(name, node, ext)
   self.symbols[name] = {
      rewrite = not self.isRoot and self:mangleName(name),
      depends = ArraySet.new(),
      contents = {},
      const = true,
      node = node,
      name = name
   }

   self.currentSymbol = name

   if ext then
      local sym = self:getSymbol(name)

      for i, v in pairs(ext) do
         sym[i] = v
      end
   end
end

---@param name string
function compiler:continueSymbol(name)
   self.currentSymbol = name
end

---@param name string
---@return symbol
function compiler:getSymbol(name)
   return self.symbols[name]
end

---@return symbol
function compiler:getCurrentSymbol()
   return self.symbols[self.currentSymbol]
end

function compiler:markExportedSymbol()
   local sym = self:getCurrentSymbol()
   sym.exported = true

   self.exports[self.currentSymbol] = sym
end

function compiler:checkUnusedSymbols()
   for name, sym in pairs(self.symbols) do
      if not sym.exported and not sym.used then
         self:unusedVar(sym.node, name)
      end
   end
end

-- Imports

---@param name string
---@param kind string
---@param ext? table<any, any>
---@return import
function compiler:import(name, kind, ext)
   local import = {
      rewrite = name and self:mangleName(name),
      import = true,
      name = name,
      kind = kind,
   }

   if ext then
      for i, v in pairs(ext) do
         import[i] = v
      end
   end

   table.insert(self.artifacts.imports, import)

   return import
end

---@param self compiler
---@param sym symbol
local function importSymDeps(self, sym)
   if sym.depends then
      for i = 1, #sym.depends do
         local dep = sym.depends[i]

         self:importSym(dep)

         importSymDeps(self, dep)
      end
   end
end

---@param sym symbol
---@param ext ext
---@return import
function compiler:importSym(sym, ext)
   local cache = self.artifacts.cache

   if cache.includedSym[sym] then
      return
   end

   cache.includedSym[sym] = true

   local import = {
      contents = sym.contents,
      rewrite = sym.rewrite,
      kind = 'Artifact',
      name = sym.name,
      used = sym.used,
      import = true,
      sym = sym
   }

   if ext then
      for i, v in pairs(ext) do
         import[i] = v
      end
   end

   table.insert(self.artifacts.imports, import)

   importSymDeps(self, sym)

   return import
end

-- Manual checks

function compiler:addCheck(fn, ...)
   table.insert(self.toCheck, { fn, { ... } })
end

function compiler:checkCustomChecks()
   for i = 1, #self.toCheck do
      local fn = self.toCheck[i]

      fn[1](self, table.unpack(fn[2]))
   end
end

-- Buffer manipulation

---@vararg string
function compiler:push(...)
   table.insert(
      self:getCurrentSymbol().contents,
      table.concat({ ... })
   )
end

---@vararg string
function compiler:pushIndent(...)
   local indent = self.config.indentType == 'space' and ' ' or '\t'
   local size = indent == ' ' and self.config.indentSize or 1

   self:push(string.rep(indent, (#self.scopes - 1) * size), ...)
end

-- Error handling

---@param msg string
---@param code string
---@param node baseNode
---@param otherFile? string
function compiler:pushErr(msg, code, node, otherFile)
   table.insert(self.artifacts.errors, {
      msg = msg,
      code = code,
      start = node.pos,
      stop = node.endpos,
      file = otherFile or self.file
   })
end

---@param node baseNode
---@param name? string
---@param extra? string
function compiler:undefinedVar(node, name, extra)
   if not self.disabledUndef then
      self:pushErr(
         'undefined variable '
            .. (name or node[1])
            .. (extra or ''),
         'undef-var',
         node
      )

      return
   end
end

---@param node baseNode
---@param name? string
function compiler:shadowVar(node, name)
   local var = self:getVar(name or node[1])

   local line = var.node and select(2, rex.calcline(self.source, var.node.pos))

   self:pushErr(
      'shadowing '
         .. (var.kind or 'variable')
         .. (var.node and ' defined at line ' .. line or ''),
      'shadow-var',
      node
   )
end

---@param node baseNode
---@param name? string
---@param otherFile? string
function compiler:unusedVar(node, name, otherFile)
   name = name or node[1]

   ---@type variable|import
   local var = self:getVar(name)

   self:pushErr(
      'unused '
         .. (var.import and 'import' or var.kind or 'variable')
         .. ' ' .. name,
      'unused-var',
      node,
      otherFile
   )
end

---@param node baseNode
---@param name? string
function compiler:unusedImport(node, name)
   name = name or node[1]

   self:pushErr(
      'unused import ' .. name,
      'unused-import',
      node
   )
end

---@param node baseNode
---@param name? string
function compiler:badStatic(node, name)
   name = name or node[1]

   self:pushErr(
      'the ' .. name .. ' method should not be marked as static',
      'bad-static',
      node
   )
end

---@param node baseNode
---@param name? string
function compiler:assignConst(node, name)
   name = name or node[1]

   self:pushErr(
      'unable to assign to constant variable ' .. name,
      'assign-const',
      node
   )
end

---@param node baseNode
function compiler:unbalancedAssign(node)
   self:pushErr(
      'unbalanced assignment',
      'unbal-assign',
      node
   )
end

---@param node baseNode
function compiler:undefinedVararg(node)
   self:pushErr(
      'usage of vararg outside of vararg function',
      'outside-vararg',
      node
   )
end

---@param node baseNode
---@param name? string
function compiler:deprecatedVar(node, name, extra)
   name = name or node[1]

   self:pushErr(
      'deprecated variable ' .. name .. (extra or ''),
      'deprecated',
      node
   )
end

---@param node baseNode
---@param extra string
function compiler:undefinedSymbol(node, extra)
   self:pushErr(
      'undefined symbol' .. (extra or ''),
      'undef-sym',
      node
   )
end

-- Variables

---@param name string
---@return variable
function compiler:getVar(name)
   local sym = self:getSymbol(name)

   if sym then
      table.insert(
         self:getCurrentSymbol().depends,
         sym
      )

      return sym
   end

   local var = self.variables[name]

   if not var then
      return
   end

   if var.__array then
      return var[#var]
   end

   return var
end

---@param var variable
---@param name string
---@param node baseNode
function compiler:validateCompat(var, name, node)
   if var.bit then
      self:deprecatedVar(node, name, ', bit operators should be used instead')

      return
   end

   if var.deprecated then
      self:deprecatedVar(node, name)

      return
   end

   -- no point in continuing if we already are have compat
   if self.artifacts.compat == 'always' then
      return
   end

   if var.compat == 'always' and not self.config.compat then
      self:undefinedVar(node, name, ', variable does\'t exist in ' .. self.config.target)

      return
   end

   if self.artifacts.compat ~= 'always' then
      self.artifacts.compat = var.compat
   end
end

---@param name string
---@param node baseNode
---@param ext ext
function compiler:pushVar(name, node, ext)
   name = name or node[1]

   local new = {
      kind = 'variable',
      file = self.file,
      node = node
   }

   if ext then
      for i, v in pairs(ext) do
         new[i] = v
      end
   end

   local var = self:getVar(name)

   if name ~= '...' and var then
      self:shadowVar(node, name)

      local raw = self.variables[name]

      if raw.__array then
         table.insert(raw, new)
      else
         self.variables[name] = {
            __array = true,
            var,
            raw
         }
      end

      return new
   end

   self.variables[name] = new

   self.scopes[#self.scopes][name] = new

   return new
end

---@param name string
---@return string
function compiler:mangleName(name)
   --; TODO - prevent __M... identifiers
   return '__M' .. name .. self.file:gsub('[/\\.]', '_')
end

-- Scopes

function compiler:inc()
   table.insert(self.scopes, {})
end

function compiler:dec()
   local scope = table.remove(self.scopes)

   self:errorUnused(scope)

   for name, var in pairs(self.variables) do
      if scope[name] then
         if var.__array and #var == 2 then
            self.variables[name] = var[1]
         elseif var.__array then
            table.remove(var)
         else
            self.variables[name] = nil
         end
      end
   end
end

---@param scope table<string, variable>
function compiler:errorUnused(scope)
   for name, var in pairs(scope) do
      if not var.used then
         self:unusedVar(var.node, name)
      end
   end
end

-- Preparation

function compiler:ClassPrepare(node)
   self:startSymbol(node[1][1], node, {
      file = self.file,
      kind = 'class',
   })
end

-- Code generation

function compiler:visit(node, ...)
   if node and self[node.tag] then
      return self[node.tag](self, node, ...)
   end
end

function compiler:Block(node)
   self:inc()

   for i = 1, #node do
      self:push('\n')

      self:visit(node[i], true)
   end

   self:push('\n')

   self:dec()
end

function compiler:Chunk(node)
   for i = 1, #node do
      self:visit(node[i], true)
   end
end

function compiler:BaseInclude(node)
   local adjustedPath = {}

   for i = 1, #node[1] do
      table.insert(adjustedPath, node[1][i][1])
   end

   -- The main file doesn't need to worry about being absolute as it should never be imported
   local luaPath = table.concat(adjustedPath, '.')

   adjustedPath = table.concat(adjustedPath, '/')

   local tried = {
      'unable to find module \'' .. adjustedPath:gsub('/', '.') .. '\''
   }

   local file

   for path in self.config.path:gmatch('[^;]+') do
      path = path
         :gsub('?', adjustedPath)
         :gsub('%.lua$', '.cb')

      local f = io.open(path, 'r')

      if not f then
         table.insert(tried, 'no file \'' .. path .. '\'')
      else
         file = { path, f }
         break
      end
   end

   if not file then
      return self:pushErr(table.concat(tried, '\n   '), 'no-module', node)
   end

   local res, err = compiler.compile(file, self.artifacts)

   if not res then
      return self:pushErr(err, 'invalid-syntax', node, adjustedPath)
   end

   local vars = {}

   for _, sym in pairs(res.exports) do
      local var = self:importSym(sym)

      table.insert(vars, var)

      self.variables[sym.name] = var
   end

   self:addCheck(checks.anyUsed, vars, node, luaPath)
end

function compiler:FromNativeRef(node)
   local path = {}

   for i = 1, #node[1] do
      table.insert(path, node[1][i][1])
   end

   local name = path[#path]

   local var = self:import(name, 'FromNativeRef', {
      path = table.concat(path, '.')
   })

   self.variables[name] = var

   self:addCheck(checks.used, var, node, name)
end

-- FromNative isn't fun
-- We have **no** idea what is being imported
-- At least FromNativeRef gives us a name
-- Using FromNative **will** give undefined variable warnings
function compiler:FromNative(node)
   if not self.disabledUndef then
      self.disabledUndef = true
   end

   local path = {}

   for i = 1, #node[1] do
      table.insert(path, node[1][i][1])
   end

   self:import(nil, 'FromNative', {
      path = table.concat(path, '.')
   })
end

function compiler:Class(node)
   local name = node[1][1]

   self:continueSymbol(name)
   self:markExportedSymbol()

   self:pushIndent(name, ' = {}\n\n')
   self:pushIndent('setmetatable(', name, ', {\n')

   self:inc()
   self:inc()

   self:pushIndent('__call = function(_, ...)\n')

   self:inc()

   self:pushIndent('local self = setmetatable({}, { __index = ', name, ' })\n')

   local hasArgs

   if node[3] then
      hasArgs = true

      for i = 1, #node[2] do
         local arg = node[2][i]
         local var = self:getVar(arg[1])

         if not var then
            self:undefinedVar(arg)
         else
            var.used = true
         end

         self:pushIndent('setmetatable(self, { __index = ', arg[1], '})\n')
      end
   end

   self:pushIndent('self:Start(...)\n')
   self:pushIndent('return self\n')

   self:dec()

   self:pushIndent('end\n')

   self:dec()
   self:dec()

   self:pushIndent('})\n')

   self:inc()

   local body = node[hasArgs and 3 or 2]

   for i = 1, #body do
      local fn = body[i]
      local fnName = fn[2][1]

      if fnName ~= 'Main' and not fn.static then
         self:pushVar(fnName, fn, {
            kind = 'method',
            const = true,
            used = true
         })
      end
   end

   local hasStart

   for i = 1, #body do
      self:push('\n')

      self:visit(body[i], node)

      local fn = body[i]
      local fnName = fn[2][1]

      if fnName == 'Main' then
         self:getCurrentSymbol().hasMain = true

         if fn.static then
            self:badStatic(fn, 'Main')
         end
      elseif fnName == 'Start' then
         hasStart = true

         if fn.static then
            self:badStatic(fn, 'Start')
         end
      end
   end

   if not hasStart then
      self:pushIndent('\nfunction ', node[1][1], ':Start() end\n')
   end

   self:dec()

   self:push('\n')
end

function compiler:FunctionCb(node, parent)
   local name = node[2][1]

   self:pushIndent('function ', parent[1][1], (node[1] and '.' or ':'), name, '(')

   self:inc()

   for i = 1, #node[3] do
      if i ~= 1 then
         self:push(', ')
      end

      local arg = node[3][i]
      local argName = arg.tag == 'Id' and arg[1] or '...'

      self:push(node[3][i][1])

      self:pushVar(argName, arg, {
         kind = 'argument'
      })
   end

   self:push(')')

   if not node.static then
      self:pushVar('this', node, {
         rewrite = 'self',
         kind = 'this',
         const = true,
         used = true
      })
   end

   for i = 1, #node[4] do
      self:push('\n')

      self:visit(node[4][i], true)
   end

   self:push('\n')

   self:dec()

   self:pushIndent('end\n')
end

function compiler:Statement(node)
   self:visit(node[1], true)
end

-- Lua code generation

function compiler:Label(node)
   self:pushIndent('::', node[1], '::')
end

function compiler:Return(node)
   self:pushIndent('return ')

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      self:visit(node[1][i])
   end
end

function compiler:Break()
   self:pushIndent('break')
end

function compiler:Goto(node)
   self:pushIndent('goto ', node[1], '')
end

function compiler:Do(node)
   self:pushIndent('do\n')

   self:visit(node[1])

   self:pushIndent('end')
end

function compiler:While(node)
   self:pushIndent('while ')

   self:visit(node[1])

   self:pushIndent(' do\n')

   self:visit(node[2])

   self:pushIndent('end')
end

function compiler:Repeat(node)
   self:pushIndent('repeat\n')

   self:inc()

   for i = 1, #node[1] do
      self:push('\n')

      self:visit(node[1][i], true)
   end

   self:push('\n')

   -- repeat has delayed scope closing
   self:push(string.rep(' ', (#self.scopes - 2) * 3) .. 'until ')

   self:visit(node[2])

   self:dec()
end

function compiler:If(node)
   self:pushIndent('if ')

   self:visit(node[1])

   self:push(' then')

   self:visit(node[2], true)

   for i = 1, #node[3] do
      local elif = node[3][i]
      self:pushIndent('elseif ')

      self:visit(elif[1])

      self:push(' then')

      self:visit(node[elif[2]], true)
   end

   if node[4] then
      self:pushIndent('else')

      self:visit(node[4], true)
   end

   self:pushIndent('end')
end

function compiler:ForNum(node)
   self:pushIndent('for ')

   self:inc()

   local name = node[1][1]

   self:pushVar(name, node)

   self:push(name, ' = ')

   self:visit(node[2])

   self:push(', ')

   self:visit(node[3])

   if node[5] then
      self:push(', ')

      self:visit(node[4])
   end

   self:push('do\n')

   local block = node[5] and node[5] or node[4]

   for i = 1, #block do
      self:push('\n')

      self:visit(block[i], true)
   end

   self:push('\n')

   self:dec()

   self:pushIndent('end')
end

function compiler:ForIn(node)
   self:pushIndent('for ')

   self:inc() -- Scope starts early to capture the loop vars

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      self:push(node[1][i][1])
   end

   self:push(' in ')

   for i = 1, #node[2] do
      if i ~= 1 then
         self:push(', ')
      end

      self:visit(node[2][i])
   end

   for i = 1, #node[1] do
      self:pushVar(node[1][i][1], node[1][i])
   end

   self:push(' do\n')

   for i = 1, #node[3] do
      self:push('\n')

      self:visit(node[3][i], true)
   end

   self:push('\n')

   self:dec()

   self:push('end')
end

function compiler:VarDecl(node)
   self:pushIndent('local ')

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      local ident = node[1][i]

      self:pushVar(ident[1], ident)

      self:push(ident[1])

      if ident[2] then
         self:push(' <')

         self:push(ident[2])

         self:push('>')
      end
   end

   if node[2] then
      self:push(' = ')

      for i = 1, #node[2] do
         if i ~= 1 then
            self:push(', ')
         end

         self:visit(node[2][i])
      end
   end
end

local function assignOp(self, node)
   self:pushIndent()

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      local left = node[1][i]

      if left.tag == 'Id' then
         local var = self:getVar(left[1])

         if var and var.const then
            self:assignConst(left)
         end
      end

      self:visit(node[1][i])
   end

   self:push(' = ')

   local toOp = #node[3] == 1 and node[3][1]

   if #node[1] ~= #node[3] and not toOp then
      -- With x, y, z = 3, it might be correct
      -- x, y, z += 1 is always incorrect
      self:unbalancedAssign(node)
   end

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      self:visit(node[1][i])

      self:push(' ', node[2], ' ')

      if toOp then
         self:visit(toOp)
      elseif node[3][i] then
         self:visit(node[3][i])
      else
         self:push('nil')
      end
   end
end

function compiler:Assign(node)
   if node[3] then
      -- Skip trying to define
      return assignOp(self, node)
   end

   local toDefine = {}
   local toAssign = {}

   local indented = false

   for i = 1, #node[1] do
      local left = node[1][i]

      if left.tag == 'Id' then
         local var = self:getVar(left[1])

         if var and var.const then
            self:assignConst(left)
         elseif not var then
            table.insert(toDefine, i)

            self:pushVar(left[1], left)
         else
            if not indented then
               indented = true
               self:pushIndent()
            end

            table.insert(toAssign, i)

            self:push(left[1])
         end
      else
         if not indented then
            indented = true
            self:pushIndent()
         end

         table.insert(toAssign, i)

         self:visit(left)
      end
   end

   if #toAssign > 0 then
      self:push(' = ')

      for i = 1, #toAssign do
         if i ~= 1 then
            self:push(', ')
         end

         self:visit(node[2][toAssign[i]])
      end
   end

   if #toDefine > 0 then
      if #toAssign > 0 then
         self:push('\n')
      end

      self:pushIndent('local ')

      for i = 1, #toDefine do
         if i ~= 1 then
            self:push(', ')
         end

         self:push(node[1][toDefine[i]][1])
      end

      self:push(' = ')

      for i = 1, #toDefine do
         if i ~= 1 then
            self:push(', ')
         end

         self:visit(node[2][toDefine[i]])
      end
   end
end

function compiler:Number(node)
   self:push(node[1])
end

function compiler:String(node)
   self:push('\'', node[1], '\'')
end

function compiler:Boolean(node)
   self:push(tostring(node[1]))
end

function compiler:Nil()
   self:push('nil')
end

function compiler:Varargs(node)
   local var = self.scopes[#self.scopes]['...']

   if var then
      var.used = true
   else
      self:undefinedVararg(node)
   end

   self:push('...')
end

function compiler:Id(node)
   local var = self:getVar(node[1])

   if not var then
      self:undefinedVar(node)

      return self:push(node[1])
   else
      var.used = true
   end

   self:validateCompat(var, node[1], node)

   if var.rewrite then
      return self:push(var.rewrite)
   end

   self:push(node[1])
end

function compiler:Function(node)
   self:push('function(')

   self:inc()

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      local arg = node[1][i]
      local name = arg.tag == 'Id' and arg[1] or '...'

      self:push(name)

      self:pushVar(name, arg, {
         kind = 'argument'
      })
   end

   self:push(')')

   local indent

   for i = 1, #node[2] do
      indent = true

      self:push('\n')

      self:visit(node[2][i], true)
   end

   if indent then
      self:push('\n')
   end

   self:dec()

   if indent then
      self:pushIndent('end')
   else
      self:push(' end')
   end
end

function compiler:Table(node)
   self:push('{ ')

   for i = 1, #node do
      if i ~= 1 then
         self:push(', ')
      end

      self:visit(node[i])
   end

   self:push(#node > 0 and ' ' or '', '}')
end

function compiler:Pair(node)
   self:push(node[1], ' = ')

   self:visit(node[2])
end

function compiler:Paren(node)
   self:push('(')

   self:visit(node[1])

   self:push(')')
end

local transformBinary = {
   ['&'] = 'band',
   ['|'] = 'bor',
   ['~'] = 'bxor',
   ['>>'] = 'rshift',
   ['<<'] = 'lshift',
}

function compiler:BinaryOp(node)
   local config = self.config

   if config.target < 5.3 and transformBinary[node[2]] then
      if config.target == 5.1 then
         if not config.compat then
            self:undefinedSymbol(node, ', enable compat to use bit operators in Lua 5.1')
         elseif not self.artifacts.bit then
            self.artifacts.bit = self:mangleName('bit')
         end
      else
         self.artifacts.bit = 'bit32'
      end

      self:push(self.artifacts.bit or 'bit', '.', transformBinary[node[2]], '(')

      self:visit(node[1])

      self:push(', ')

      self:visit(node[3])

      self:push(')')

      return
   end

   self:visit(node[1])

   local space = node[2] == '^' and '' or ' '

   self:push(space, node[2], space)

   self:visit(node[3])
end

function compiler:UnaryOp(node)
   if self.config.target < 5.3 and node[1] == '~' then
      self:push(self.artifacts.bit, '.bnot(')
      self:visit(node[2])
      self:push(')')
   end

   self:push(node[1], node[1] == 'not' and ' ' or '')

   self:visit(node[2])
end

local drillable = {
   KeyIndex = 2,
   DotIndex = 2,
   ColonIndex = 2,
   CallMethod = 3,
   CallIndex = 3,
}

local function drill(node, children)
   children = children or {}

   table.insert(children, node[1])

   local pos = drillable[node.tag]

   if pos then
      drill(node[pos], children)
   end

   return children
end

---@param self compiler
local function assemblyPath(self, node, hasMethod)
   local path = drill(node)

   for i = #path, 1, -1 do
      local element = path[i]

      if i == #path then
         local var = self:getVar(element)

         if not var then
            self:undefinedVar(node, element)
         elseif var.rewrite then
            element = var.rewrite
         end

         if var then
            var.used = true

            self:validateCompat(var, element, node)
         end
      end

      if type(element) == 'string' then
         if not hasMethod and i ~= #path then
            self:push('.')
         elseif hasMethod and i == 1 then
            self:push(':')
         end

         self:push(element)
      else
         self:push('[')

         self:visit(element)

         self:push(']')
      end
   end
end

function compiler:DotIndex(node)
   assemblyPath(self, node)
end

function compiler:Call(node, parent)
   if parent then
      self:pushIndent()
   end

   local name = node[2][1]
   local var = self:getVar(name)

   if var and var.kind == 'method' then
      var.used = true
      self:push('self:', name)
   else
      assemblyPath(self, node[2])
   end

   if var and var.kind == 'class' then
      var.used = true
   end

   self:push('(')

   for i = 1, #node[1] do
      if i ~= 1 then
         self:push(', ')
      end

      self:visit(node[1][i])
   end

   self:push(')')
end

function compiler:CallMethod(node, parent)
   if parent then
      self:pushIndent()
   end

   assemblyPath(self, node, true)

   self:push('(')

   for i = 1, #node[2] do
      if i ~= 1 then
         self:push(', ')
      end

      self:visit(node[2][i])
   end

   self:push(')')
end

return compiler
