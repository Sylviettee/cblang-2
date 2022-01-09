-- A set that acts like an array
-- Uses 2 tables for O(1) lookups of keys or values

---@class ArraySet
---@field arr table<any, any>
---@field set table<any, any>
local ArraySet = {}

---@param arr table<any, any>
function ArraySet.new(arr)
   arr = arr or {}

   local self = setmetatable({ arr = {}, set = {} }, ArraySet)

   for i = 1, #arr do
      table.insert(self, arr[i])
   end

   return self
end

-- Static to prevent name collisions
---@param set Set
---@param name any
function ArraySet.has(set, name)
   return set.set[name]
end

function ArraySet:__index(iOrV)
   return self.arr[iOrV] or self.set[iOrV]
end

function ArraySet:__newindex(index, value)
   if self.set[value] then
      return
   end

   local prevValue = not value and self.arr[index]

   self.arr[index] = value

   if value then
      self.set[value] = index

      return
   end

   local last, i

   for k, v in pairs(self.set) do
      if v == last then
         self.set[i] = nil

         return
      end

      last = v
      i = k
   end

   self.set[prevValue] = nil
end

function ArraySet:__len()
   return #self.arr
end

function ArraySet:__pairs()
   return next, self.arr, nil
end

return ArraySet
