--[[
  Pandoc Lua filter to convert horizontal rules to simple lines
  instead of page breaks
]]

function HorizontalRule()
  -- Replace horizontal rule with a simple centered line
  return pandoc.RawBlock("latex", "\\vspace{0.5cm}\\noindent\\rule{\\textwidth}{0.4pt}\\vspace{0.5cm}")
end
