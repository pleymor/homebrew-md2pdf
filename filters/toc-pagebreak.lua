-- Lua filter to add a page break after the table of contents
-- This works by injecting raw LaTeX after pandoc generates the TOC

function Pandoc(doc)
  -- Insert a raw LaTeX pagebreak at the beginning of the document body
  -- This will appear right after the TOC since pandoc places TOC before body
  local pagebreak = pandoc.RawBlock('latex', '\\newpage')
  table.insert(doc.blocks, 1, pagebreak)
  return doc
end
