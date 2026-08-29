--[[
  Pandoc Lua filter for GitHub-style alerts/admonitions
  Converts > [!NOTE], > [!TIP], > [!IMPORTANT], > [!WARNING], > [!CAUTION]
  to styled LaTeX boxes using tcolorbox, or to paragraphs carrying the
  Alert* styles from templates/reference.docx in docx output
]]

local alert_types = {
  NOTE = {
    title = "Note",
    color = "blue!10",
    frame_color = "blue!50!black"
  },
  TIP = {
    title = "Tip",
    color = "green!10",
    frame_color = "green!50!black"
  },
  IMPORTANT = {
    title = "Important",
    color = "purple!10",
    frame_color = "purple!50!black"
  },
  WARNING = {
    title = "Warning",
    color = "orange!10",
    frame_color = "orange!50!black"
  },
  CAUTION = {
    title = "Caution",
    color = "red!10",
    frame_color = "red!50!black"
  }
}

---Reads the alert type off the start of an inline list.
---@param inlines table the first block's inlines
---@return string|nil
local function detect_alert_type(inlines)
  local first = inlines[1]
  if not first or first.t ~= "Str" then
    return nil
  end
  local alert = first.text:match("^%[!(%u+)%]")
  if alert and alert_types[alert] then
    return alert
  end
  return nil
end

---Drops the "[!TYPE]" marker, keeping every other inline as it is so bold,
---italic, code spans and links inside the alert survive.
---@param inlines table the first block's inlines
---@param alert_type string
---@return table inlines
local function remove_alert_marker(inlines, alert_type)
  local kept = {}
  local first_index = 2

  local leftover = inlines[1].text:gsub("^%[!" .. alert_type .. "%]%s*", "")
  if leftover ~= "" then
    table.insert(kept, pandoc.Str(leftover))
  else
    -- The marker had a line of its own: drop the break that followed it too
    local following = inlines[2]
    local is_break = following ~= nil
      and (following.t == "Space" or following.t == "SoftBreak" or following.t == "LineBreak")
    if is_break then
      first_index = 3
    end
  end

  for i = first_index, #inlines do
    table.insert(kept, inlines[i])
  end
  return kept
end

---Counts the marked items so every bookmark gets a name of its own.
local marked_item_count = 0

---Wraps each item of a list in a Div named after the alert style.
---@param list table a BulletList or OrderedList
---@param style string the Alert* style the items belong to
---@return table list
local function mark_items(list, style)
  local items = {}
  for _, item in ipairs(list.content) do
    marked_item_count = marked_item_count + 1
    local id = string.format("md2pdf-alert-%s-%d", style, marked_item_count)
    items[#items + 1] = { pandoc.Div(item, pandoc.Attr(id, {}, {})) }
  end
  list.content = items
  return list
end

---Wraps every list item of a block in an identified Div, at any nesting depth.
---
---Pandoc drops a custom-style Div placed inside a list item, so the alert
---styling cannot reach the item that way. An id survives as a block-level
---bookmark around the item's paragraphs, which scripts/patch_alert_lists.py
---then turns into the real paragraph style.
---@param block table a block from the alert body
---@param style string the Alert* style the items belong to
---@return table block
local function mark_list_items(block, style)
  -- walk_block only visits the descendants, so a list sitting straight in the
  -- alert has to be marked on its own after its nested lists have been.
  local walked = pandoc.walk_block(block, {
    BulletList = function(list) return mark_items(list, style) end,
    OrderedList = function(list) return mark_items(list, style) end,
  })
  if walked.t == "BulletList" or walked.t == "OrderedList" then
    return mark_items(walked, style)
  end
  return walked
end

function BlockQuote(el)
  if #el.content == 0 then
    return el
  end

  local first_block = el.content[1]
  if first_block.t ~= "Para" and first_block.t ~= "Plain" then
    return el
  end

  local alert_type = detect_alert_type(first_block.content)

  if not alert_type then
    return el
  end

  local config = alert_types[alert_type]

  -- Remove the alert marker from the first paragraph
  local cleaned_inlines = remove_alert_marker(first_block.content, alert_type)

  -- Rebuild content without the marker
  local new_content = pandoc.List()

  if #cleaned_inlines > 0 then
    new_content:insert(
      first_block.t == "Plain" and pandoc.Plain(cleaned_inlines) or pandoc.Para(cleaned_inlines)
    )
  end

  for i = 2, #el.content do
    new_content:insert(el.content[i])
  end

  if FORMAT == "docx" then
    local style = "Alert" .. config.title
    local blocks = pandoc.List()
    blocks:insert(pandoc.Para(pandoc.Strong(pandoc.Str(config.title))))
    for _, block in ipairs(new_content) do
      blocks:insert(mark_list_items(block, style))
    end
    return pandoc.Div(blocks, pandoc.Attr("", {}, { ["custom-style"] = style }))
  end

  -- Create LaTeX box
  local latex_begin = string.format(
    "\\begin{tcolorbox}[colback=%s, colframe=%s, title=%s, fonttitle=\\bfseries, "
    .. "boxrule=0.5pt, arc=2pt, left=6pt, right=6pt, top=4pt, bottom=4pt]\n",
    config.color, config.frame_color, config.title
  )
  local latex_end = "\n\\end{tcolorbox}"

  local result = pandoc.List()
  result:insert(pandoc.RawBlock("latex", latex_begin))
  for _, block in ipairs(new_content) do
    result:insert(block)
  end
  result:insert(pandoc.RawBlock("latex", latex_end))

  return result
end
