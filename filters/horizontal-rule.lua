--[[
  Pandoc Lua filter to convert horizontal rules to page breaks
]]

---Converts horizontal rules (---) to a page break in the output format.
---@return pandoc.RawBlock Page break raw block (openxml for docx, latex otherwise)
function HorizontalRule()
  if FORMAT == "docx" then
    return pandoc.RawBlock("openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
  end
  return pandoc.RawBlock("latex", "\\newpage")
end
