if not table.move then
   ---@param a1 table
   ---@param f number
   ---@param e number
   ---@param t number
   ---@param a2? table
   ---@return table a2
   table.move = function(a1, f, e, t, a2)
      -- default to a1 as dest
      a2 = a2 or a1

      -- if we actually have elements to move
      if e > f then
         -- Starts at zero since offset
         local start, stop, decrement = 0, e - f, 1

         if t > f then
            start, stop, decrement = stop, start, -1
         end

         for i = start, stop, decrement do
            a2[t + i] = a1[f + i]
         end
      end
   end
end

if not table.unpack then
   table.unpack = table.unpack or unpack
end
