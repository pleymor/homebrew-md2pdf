--[[
  Pandoc Lua filter to convert horizontal rules to page breaks
]]

---Converts horizontal rules (---) to LaTeX page breaks.
---@return pandoc.RawBlock LaTeX page break command
function HorizontalRule()
  return pandoc.RawBlock("latex", "\\newpage")
end
