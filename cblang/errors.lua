local errors = {
   ['Eof'] = 'expected end of file',
   [';'] = 'expected `;`',
   ['Path'] = 'expected a file path',
   ['native'] = 'expected `native`',
   ['reference'] = 'expected `reference` or `include`',
   ['Id'] = 'expected identifier',
   ['{'] = 'expected `{`',
   ['}'] = 'expected `}`',
   ['Args'] = 'expected function parameters',
   ['('] = 'expected `(`',
   [')'] = 'expected `)`',
   ['NameOrVararg'] = 'expected identifier or `...`',
   ['NoMangle'] = 'identifiers starting with `__M` are reserved',
   ['NAME'] = 'expected identifier',
   ['::'] = 'expected `::`',
   ['expr'] = 'expected expression',
   ['idlist'] = 'expected identifier(s)',
   ['exprlist'] = 'expected expression(s)',
   ['callargs'] = 'expected function arguments',
   ['IdDecl'] = 'expected identifier',
   ['var'] = 'expected variable',
   ['exprand'] = 'expected expression',
   ['exprcmp'] = 'expected expression',
   ['exprbor'] = 'expected expression',
   ['exprbxor'] = 'expected expression',
   ['exprband'] = 'expected expression',
   ['exprbshift'] = 'expected expression',
   ['exprconcat'] = 'expected expression',
   ['exprfact'] = 'expected expression',
   ['exprunary'] = 'expected expression',
   ['LONG_CLOSE'] = 'unclosed long string or comment',
   ['QUOTE_CLOSE'] = 'unclosed string',
   ['ESCAPE'] = 'malformed escape sequence',
   ['HEX_PREFIX'] = 'malformed hexadecimal number',
   ['EXP_DIGITS'] = 'malformed exponential number',
}

local formatted = {}

for i, v in pairs(errors) do
   formatted['Expected_' .. i] = v
end

return formatted
