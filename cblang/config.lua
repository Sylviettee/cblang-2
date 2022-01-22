return {
   indentType = 'space',
   indentSize = 3,
   target = 'Lua 5.1',
   compat = true,

   path = os.getenv('CB_PATH') or package.path:gsub('%.lua', '.cb')
}
