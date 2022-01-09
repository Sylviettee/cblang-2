return {
   indentType = 'space',
   indentSize = 3,

   path = os.getenv('CB_PATH') or package.path:gsub('%.lua', '.cb')
}
