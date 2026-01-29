--[[
  Pandoc Lua filter to remove page breaks around figures/images
  This filter runs after mermaid-filter and removes \newpage, \clearpage
  commands that might cause blank pages, and keeps headings with their content
]]

function RawBlock(el)
  if el.format == "latex" then
    -- Remove standalone page break commands
    local content = el.text
    -- Check if this block is just a page break command
    if content:match("^%s*\\newpage%s*$") or
       content:match("^%s*\\clearpage%s*$") or
       content:match("^%s*\\pagebreak%s*$") then
      return {}  -- Remove the block entirely
    end
    -- Remove page breaks from within other LaTeX content
    content = content:gsub("\\newpage", "")
    content = content:gsub("\\clearpage", "")
    content = content:gsub("\\pagebreak", "")
    if content ~= el.text then
      return pandoc.RawBlock("latex", content)
    end
  end
  return el
end
