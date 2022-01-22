require 'cblang.minicompat'

local compiler = require 'cblang.compiler'
local config = require 'cblang.config'
local rex = require 'lpegrex'

local bit32Override = { 'local M = {}' }

do
   local binOp = {
      ['&'] = 'band',
      ['|'] = 'bor',
      ['~'] = 'bxor',
      ['>>'] = 'rshift',
      ['<<'] = 'lshift',
   }

   for op, name in pairs(binOp) do
      table.insert(bit32Override, 'function M.' .. name .. '(a, b) return a ' .. op .. ' b end')
   end

   table.insert(bit32Override, 'function M.bnot(a) return ~a end')

   table.insert(bit32Override, 'return M')
end

local function usage()
   io.write('Usage: cb <command> <args>\n')
   io.write('Commands:\n')
   io.write('\tbuild\tBuild the CBLang-2 script into a Lua file\n')
   io.write('\trun\tRuns the CBLang-2 script\n')
end

local function compile(file, isRan)
   local res, err = compiler.compile(file, nil, true)

   if not res then
      io.stderr:write(err .. '\n')
      os.exit(-1)
   end

   local artifacts = res.artifacts

   local buff = {}

   local hoist = {}

   local loader = {}

   local indent = config.indentType == 'space' and ' ' or '\t'
   local size = indent == ' ' and config.indentSize or 1
   local single = string.rep(indent, size)

   for i = 1, #artifacts.imports do
      local import = artifacts.imports[i]

      if import.used then
         if import.kind == 'FromNative' then
            table.insert(loader, '__Mimport(require(\'' .. import.path .. '\'))')
         else
            table.insert(hoist, import.rewrite)
         end

         if import.kind == 'FromNativeRef' then
            table.insert(buff, import.rewrite .. ' = require(\'' .. import.path .. '\')\n\n')
         elseif import.kind == 'Artifact' then
            local contents = table.concat(import.contents)

            contents = single .. contents
               :sub(1, #contents - 2)
               :gsub('\n', '\n' .. single)
               :gsub('\n%s+\n', '\n\n')

            table.insert(buff, 'do\n')
            table.insert(buff, single .. 'local ' .. import.name .. '\n')
            table.insert(buff, contents .. '\n\n')
            table.insert(buff, single .. import.rewrite .. ' = ' .. import.name)
            table.insert(buff, '\nend\n\n')
         end
      end
   end

   for i, v in pairs(res.symbols) do
      table.insert(hoist, v.rewrite or i)

      table.insert(buff, table.concat(v.contents))
   end

   if #loader > 0 then
      table.insert(buff, 1, table.concat(loader, '\n') .. '\n\n')

      table.insert(
         buff,
         1,
         'local function __Mimport(t)\n' ..
         single .. 'for i, v in pairs(t) do\n' ..
         single .. single .. ' _G[i] = v\n' ..
         single .. 'end\n' ..
         'end\n\n'
      )
   end

   -- Someday this could be included in some prelude file
   do
      local versionCheck = '(tonumber(_VERSION:sub(-3)) or 0)'
      local lua53Check = versionCheck .. ' < 5.3'

      if artifacts.compat == 'always' then
         table.insert(
            buff,
            1,
            -- TODO; bundle compat53 instead of requiring it
            'if ' .. lua53Check .. ' and not pcall(require, \'compat53\') then\n' ..
            single .. 'error(\'compat53 is required by this program\')\n' ..
            'end\n\n'
         )
      elseif artifacts.compat == 'maybe' then
         table.insert(
            buff,
            1,
            'if ' .. lua53Check .. ' then\n' ..
            single .. 'pcall(require, \'compat53\')\n' ..
            'end\n\n'
         )
      end

      if artifacts.bit then
         local bitMangle = artifacts.bit

         table.insert(
            buff,
            1,
            'if _VERSION == \'Lua 5.1\' and not pcall(require, \'bit\') then\n' ..
            single .. 'error(\'luabitop is required by this program\')\n' ..
            'elseif _VERSION == \'Lua 5.1\' then\n' ..
            single .. bitMangle .. ' = require \'bit\'\n' ..
            'elseif _VERSION == \'Lua 5.2\' then\n' ..
            single .. '---@diagnostic disable-next-line: undefined-global\n' ..
            single .. bitMangle .. ' = bit32\n' ..
            'elseif ' .. versionCheck .. ' > 5.2 then\n' ..
            single .. bitMangle .. ' = load([[\n' ..
            single .. single .. table.concat(bit32Override, '\n' .. single ..single) .. '\n' ..
            single .. ']])()\n' ..
            'end\n\n'
         )

         table.insert(hoist, bitMangle)
      end
   end

   table.insert(buff, 1, 'local ' .. table.concat(hoist, ', ') .. '\n\n')

   local mainExport = res.exports.Main

   if not isRan and mainExport and mainExport.hasMain then
      table.insert(
         buff,
         'if not pcall(debug.getlocal, 4, 1) then\n' ..
         single ..'Main():Main(...)\n' ..
         'end\n\n'
      )
   elseif isRan and mainExport and mainExport.hasMain then
      table.insert(buff, 'Main():Main(...)\n')
   elseif isRan and mainExport then
      res:pushErr(
         'Main method not found',
         'no-main',
         mainExport.node
      )
   elseif isRan then
      res:pushErr(
         'Main class not found',
         'no-main',
         {
            pos = 1,
            endpos = #res.source
         }
      )
   end

   if next(res.exports) then
      table.insert(buff, 'return {')

      for i in pairs(res.exports) do
         table.insert(buff, '\n' .. single .. i .. ' = ' .. i .. ',')
      end

      table.insert(buff, '\n}\n')
   end

   buff = '---@diagnostic disable: redundant-parameter\n' .. table.concat(buff)

   for i = 1, #artifacts.errors do
      local e = artifacts.errors[i]

      local line, col = rex.calcline(artifacts.files[e.file].source, e.start)

      io.stderr:write(
         string.format(
            '%s:%u:%u - warning[%s]: %s\n',
            e.file,
            line,
            col,
            e.code,
            e.msg
         )
      )
   end

   return buff
end

local function main(mode, input, output)
   if not mode then
      usage()

      os.exit(-1)
   end

   if not input then
      if mode == 'build' then
         io.write('Usage: cb build <input> [output]\n')
      elseif mode == 'run' then
         io.write('Usage: cb run <input>\n')
      else
         usage()
      end

      os.exit(-1)
   end

   if mode == 'run' then
      config.target = _VERSION
   end

   local out = compile(input, mode == 'run')

   if mode == 'build' then
      if not output then
         output = (input:match('^(.-)%.cb$') or input) .. '.lua'
      end

      do
         local f = assert(io.open(output, 'w'))

         f:write(out)

         f:close()
      end

      io.stdout:write('Wrote to ' .. output .. '\n')
   elseif mode == 'run' then
      load(out)(table.unpack(table.move(arg, 3, #arg, 1, {})))
   else
      usage()

      os.exit(-1)
   end
end

main(...)
