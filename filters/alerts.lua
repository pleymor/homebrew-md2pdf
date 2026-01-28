--[[
  Pandoc Lua filter for GitHub-style alerts/admonitions
  Converts > [!NOTE], > [!TIP], > [!IMPORTANT], > [!WARNING], > [!CAUTION]
  to styled LaTeX boxes using tcolorbox
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

---@param text string
---@return string|nil
local function detect_alert_type(text)
  local alert = text:match("^%[!(%u+)%]")
  if alert and alert_types[alert] then
    return alert
  end
  return nil
end

---@param text string
---@param alert_type string
---@return string
local function remove_alert_marker(text, alert_type)
  return text:gsub("^%[!" .. alert_type .. "%]%s*", "")
end

function BlockQuote(el)
  if #el.content == 0 then
    return el
  end

  local first_block = el.content[1]
  if first_block.t ~= "Para" and first_block.t ~= "Plain" then
    return el
  end

  local first_inline = first_block.content[1]
  if not first_inline or first_inline.t ~= "Str" then
    return el
  end

  local first_text = pandoc.utils.stringify(first_block)
  local alert_type = detect_alert_type(first_text)

  if not alert_type then
    return el
  end

  local config = alert_types[alert_type]

  -- Remove the alert marker from the first paragraph
  local cleaned_text = remove_alert_marker(first_text, alert_type)

  -- Rebuild content without the marker
  local new_content = pandoc.List()

  if cleaned_text ~= "" then
    new_content:insert(pandoc.Para(pandoc.Str(cleaned_text)))
  end

  for i = 2, #el.content do
    new_content:insert(el.content[i])
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
