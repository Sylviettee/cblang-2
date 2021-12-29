local compile = require 'cblang.compile'

local mode, input, output = ...

if not mode then
   io.stdout:write('Usage: cb ...\n')
   io.stderr:write('Commands:\n')
   io.stderr:write('\tbuild\tBuild the CBLang-2 script into a Lua file\n')
   io.stderr:write('\trun\tRuns the CBLang-2 script\n')

   os.exit(-1)
end

if not input then
   if mode == 'build' then
      io.stderr:write('Usage: cb build <input> [output]\n')
   elseif mode == 'run' then
      io.stderr:write('Usage: cb run <input>\n')
   end

   os.exit(-1)
end

if not output then
   output = (input:match('^(.-)%..*$') or input) .. '.lua'
end

local contents

do
   local f = assert(io.open(input, 'r'))

   contents = f:read('*a')

   f:close()
end

local out, err = compile(contents, input)

if #err > 0 then
   io.stderr:write('Warnings:\n')

   if type(err) == 'table' then
      io.stderr:write(table.concat(err, '\n') .. '\n')
   else
      -- Syntax error
      io.stderr:write(err .. '\n')

      os.exit(-1)
   end
end

if mode == 'build' then
   do
      local f = assert(io.open(output, 'w'))

      f:write(out)

      f:close()
   end

   io.stdout:write('Wrote to ' .. output .. '\n')
else
   load(out)()
end
