--[[
  Pandoc Lua filter (docx only) that builds a cover page from metadata
  (titlelogo, title, author, date) and injects a native Word TOC field.
  The TOC populates when fields are updated in Word (select all, then F9).
]]

local PAGEBREAK = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'

local TOC_FIELD = table.concat({
  '<w:sdt><w:sdtPr><w:docPartObj>',
  '<w:docPartGallery w:val="Table of Contents"/><w:docPartUnique/>',
  '</w:docPartObj></w:sdtPr><w:sdtContent>',
  '<w:p><w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>',
  '<w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h \\z \\u </w:instrText></w:r>',
  '<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
  '<w:r><w:t>Table of contents: select all (Ctrl/Cmd+A) then press F9 to populate.</w:t></w:r>',
  '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>',
  '</w:sdtContent></w:sdt>',
})

---Wraps a block in a Div carrying a docx paragraph style.
---@param style string Paragraph style id from reference.docx
---@param block table Pandoc Block
---@return table Pandoc Div
local function styled(style, block)
  return pandoc.Div({ block }, pandoc.Attr("", {}, { ["custom-style"] = style }))
end

---Builds the cover page and TOC, prepending them to the document.
---@param doc table Pandoc document
---@return table Modified Pandoc document
function Pandoc(doc)
  if FORMAT ~= "docx" then
    return doc
  end

  local meta = doc.meta
  local front = pandoc.List()

  if meta.titlelogo then
    local logo = pandoc.utils.stringify(meta.titlelogo)
    local img = pandoc.Image({}, logo, "", pandoc.Attr("", {}, { width = "6cm" }))
    front:insert(styled("TitleLogo", pandoc.Para(img)))
  end
  if meta.title then
    front:insert(styled("Title", pandoc.Para(pandoc.Str(pandoc.utils.stringify(meta.title)))))
  end
  if meta.author then
    front:insert(styled("Author", pandoc.Para(pandoc.Str(pandoc.utils.stringify(meta.author)))))
  end
  if meta.date then
    front:insert(styled("Date", pandoc.Para(pandoc.Str(pandoc.utils.stringify(meta.date)))))
  end

  if #front > 0 then
    front:insert(pandoc.RawBlock("openxml", PAGEBREAK))
  end

  front:insert(pandoc.RawBlock("openxml", TOC_FIELD))
  front:insert(pandoc.RawBlock("openxml", PAGEBREAK))

  for _, block in ipairs(doc.blocks) do
    front:insert(block)
  end

  -- Clear metadata so the docx writer doesn't render its own title block
  meta.title = nil
  meta.author = nil
  meta.date = nil

  return pandoc.Pandoc(front, meta)
end
