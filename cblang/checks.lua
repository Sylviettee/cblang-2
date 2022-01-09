local checks = {}

---@param compiler compiler
---@param arr variable[]
---@param import baseNode
---@param name string
function checks.anyUsed(compiler, arr, import, name)
   for i = 1, #arr do
      local item = arr[i]

      if item.used then
         return
      end
   end

   compiler:unusedImport(import, name)
end

---@param compiler compiler
---@param var variable
---@param import baseNode
---@param name string
function checks.used(compiler, var, import, name)
   if not var.used then
      compiler:unusedImport(import, name)
   end
end

return checks
