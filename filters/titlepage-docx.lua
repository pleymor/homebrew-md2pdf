--[[
  Pandoc Lua filter (docx only) that builds a cover page from metadata
  (titlelogo, title, author, date) and injects a native Word TOC field.
  md2pdf.sh flags the document's fields for refresh, so Word fills the TOC in
  when the document opens; the placeholder below only shows if it does not.
]]

local PAGEBREAK = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'

local MAX_TOC_LEVEL = 3

local SDT_OPEN = table.concat({
  '<w:sdt><w:sdtPr><w:docPartObj>',
  '<w:docPartGallery w:val="Table of Contents"/><w:docPartUnique/>',
  '</w:docPartObj></w:sdtPr><w:sdtContent>',
})
local SDT_CLOSE = "</w:sdtContent></w:sdt>"

-- Opening the field: everything up to the separator, after which comes the
-- result Word displays as-is until someone refreshes the field.
local FIELD_BEGIN = table.concat({
  '<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>',
  '<w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h \\z \\u </w:instrText></w:r>',
  '<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
})
local FIELD_END = '<w:r><w:fldChar w:fldCharType="end"/></w:r>'

---Escapes text for inclusion in raw OOXML.
---@param text string
---@return string
local function escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

---Collects the headings a TOC lists, numbered the way pandoc numbers them
---with --number-sections.
---@param blocks table Pandoc Blocks
---@return table entries List of {level, anchor, label}
local function collect_entries(blocks)
  local counters = {}
  for level = 1, MAX_TOC_LEVEL do
    counters[level] = 0
  end

  local entries = {}
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level <= MAX_TOC_LEVEL then
      local label = pandoc.utils.stringify(block.content)

      if not block.classes:includes("unnumbered") then
        counters[block.level] = counters[block.level] + 1
        for deeper = block.level + 1, MAX_TOC_LEVEL do
          counters[deeper] = 0
        end
        local number = {}
        for level = 1, block.level do
          table.insert(number, counters[level])
        end
        label = table.concat(number, ".") .. " " .. label
      end

      table.insert(entries, { level = block.level, anchor = block.identifier, label = label })
    end
  end
  return entries
end

---Renders one TOC entry as a paragraph linking to its heading.
---@param entry table {level, anchor, label}
---@param prefix string Raw OOXML to insert before the entry text
---@param suffix string Raw OOXML to insert after the entry text
---@return string xml
local function entry_xml(entry, prefix, suffix)
  return string.format(
    '<w:p><w:pPr><w:pStyle w:val="TOC%d"/></w:pPr>%s'
    .. '<w:hyperlink w:anchor="%s"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>'
    .. '<w:t xml:space="preserve">%s</w:t></w:r></w:hyperlink>%s</w:p>',
    entry.level, prefix, escape(entry.anchor), escape(entry.label), suffix
  )
end

---Builds the TOC: a real Word field whose stored result already lists every
---heading, so readers see it without refreshing anything. Page numbers are the
---one part only a layout engine can produce; they appear once fields update.
---@param blocks table Pandoc Blocks
---@return string xml
local function toc_field(blocks)
  local entries = collect_entries(blocks)

  if #entries == 0 then
    return SDT_OPEN
      .. "<w:p>" .. FIELD_BEGIN
      .. "<w:r><w:t>Table of contents</w:t></w:r>"
      .. FIELD_END .. "</w:p>"
      .. SDT_CLOSE
  end

  local paragraphs = {}
  for index, entry in ipairs(entries) do
    local prefix = index == 1 and FIELD_BEGIN or ""
    local suffix = index == #entries and FIELD_END or ""
    table.insert(paragraphs, entry_xml(entry, prefix, suffix))
  end

  return SDT_OPEN .. table.concat(paragraphs) .. SDT_CLOSE
end

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

  front:insert(pandoc.RawBlock("openxml", toc_field(doc.blocks)))
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
