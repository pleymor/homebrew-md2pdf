--[[
  Pandoc Lua filter for GitHub-style task lists in docx output

  Pandoc turns "- [ ] item" into a bullet-list item whose text starts with a
  ☐/☒ glyph, so Word shows a bullet *and* a box. This replaces each task item
  with a bullet-free paragraph (Checklist style from templates/reference.docx)
  holding a real Word checkbox content control, which readers can tick.

  Other output formats are left to pandoc's own rendering.
]]

local UNCHECKED_GLYPH = "\u{2610}" -- ☐
local CHECKED_GLYPH = "\u{2612}"   -- ☒

-- Word renders checkbox content controls with MS Gothic, shipped with Office.
local GLYPH_FONT = "MS Gothic"

-- Pandoc's docx writer emits a fixed namespace list on <w:document>, so the
-- Word 2010 namespace has to be declared on the raw element itself.
local W14_NS = "http://schemas.microsoft.com/office/word/2010/wordml"

-- Content controls need a document-unique id.
local next_control_id = 900000

---Builds the OOXML for an inline, clickable checkbox content control.
---@param checked boolean whether the box starts out ticked
---@return string xml
local function checkbox_xml(checked)
  next_control_id = next_control_id + 1
  local glyph = checked and CHECKED_GLYPH or UNCHECKED_GLYPH
  return string.format(
    '<w:sdt xmlns:w14="%s">'
    .. '<w:sdtPr><w:id w:val="%d"/>'
    .. '<w14:checkbox>'
    .. '<w14:checked w14:val="%d"/>'
    .. '<w14:checkedState w14:val="2612" w14:font="%s"/>'
    .. '<w14:uncheckedState w14:val="2610" w14:font="%s"/>'
    .. '</w14:checkbox></w:sdtPr>'
    .. '<w:sdtContent><w:r><w:rPr>'
    .. '<w:rFonts w:ascii="%s" w:hAnsi="%s" w:eastAsia="%s"/>'
    .. '</w:rPr><w:t>%s</w:t></w:r></w:sdtContent></w:sdt>',
    W14_NS, next_control_id, checked and 1 or 0,
    GLYPH_FONT, GLYPH_FONT, GLYPH_FONT, GLYPH_FONT, GLYPH_FONT, glyph
  )
end

---Tells whether a list item is a task item, and in which state.
---@param blocks table the item's blocks
---@return "checked"|"unchecked"|nil
local function task_state(blocks)
  local first = blocks[1]
  if not first or (first.t ~= "Plain" and first.t ~= "Para") then
    return nil
  end

  local first_inline = first.content[1]
  if not first_inline or first_inline.t ~= "Str" then
    return nil
  end

  if first_inline.text == CHECKED_GLYPH then
    return "checked"
  elseif first_inline.text == UNCHECKED_GLYPH then
    return "unchecked"
  end
  return nil
end

---Rewrites a task item as a styled, bullet-free block with a checkbox.
---@param blocks table the item's blocks
---@param checked boolean whether the box starts out ticked
---@return table div
local function to_checklist_block(blocks, checked)
  local first = blocks[1]

  -- Keep the glyph pandoc inserted out, along with the space that followed it
  local skip = 1
  if first.content[2] and first.content[2].t == "Space" then
    skip = 2
  end

  local inlines = { pandoc.RawInline("openxml", checkbox_xml(checked)), pandoc.Space() }
  for i = skip + 1, #first.content do
    table.insert(inlines, first.content[i])
  end

  local new_blocks = {
    first.t == "Para" and pandoc.Para(inlines) or pandoc.Plain(inlines)
  }
  for i = 2, #blocks do
    table.insert(new_blocks, blocks[i])
  end

  return pandoc.Div(new_blocks, pandoc.Attr("", {}, { ["custom-style"] = "Checklist" }))
end

function BulletList(el)
  if FORMAT ~= "docx" then
    return nil
  end

  local result = pandoc.List()
  local plain_items = pandoc.List()
  local found_task = false

  -- Items that are not task items keep their bullet, so consecutive runs of
  -- them are put back into a list of their own.
  local function flush_plain_items()
    if #plain_items > 0 then
      result:insert(pandoc.BulletList(plain_items))
      plain_items = pandoc.List()
    end
  end

  for _, item in ipairs(el.content) do
    local state = task_state(item)
    if state then
      found_task = true
      flush_plain_items()
      result:insert(to_checklist_block(item, state == "checked"))
    else
      plain_items:insert(item)
    end
  end
  flush_plain_items()

  if not found_task then
    return nil
  end
  return result
end
