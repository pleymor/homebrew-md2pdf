--[[
  Pandoc Lua filter for auto-fit table columns.
  Calculates column widths proportional to content length
  instead of using equal-width columns.
]]

--- Extracts plain text length from a list of Pandoc Blocks.
--- @param blocks table List of Pandoc Block elements
--- @return number Character count of the stringified content
local function content_length(blocks)
  local text = pandoc.utils.stringify(pandoc.Pandoc(blocks))
  return utf8.len(text) or #text
end

--- Renders a list of Pandoc Blocks to LaTeX.
--- @param blocks table List of Pandoc Block elements
--- @return string LaTeX string
local function blocks_to_latex(blocks)
  local doc = pandoc.Pandoc(blocks)
  local rendered = pandoc.write(doc, "latex")
  -- Remove trailing newlines from pandoc output
  return rendered:gsub("%s+$", "")
end

--- Maps a Pandoc alignment to a LaTeX column spec prefix.
--- @param align string Pandoc alignment value
--- @return string LaTeX alignment character (l, r, c, or empty for paragraph)
local function align_prefix(align)
  if align == "AlignRight" then return "r"
  elseif align == "AlignCenter" then return "c"
  elseif align == "AlignLeft" then return "l"
  else return "l"
  end
end

--- Builds a LaTeX column spec with all columns proportional to content,
--- guaranteeing the total fits exactly within \textwidth.
--- @param max_lengths table Max content lengths per column
--- @param aligns table Pandoc alignment per column
--- @param num_cols number Number of columns
--- @return string LaTeX column specification
local function build_colspec(max_lengths, aligns, num_cols)
  local min_width = 0.06
  -- Reserve space for inter-column padding: 2 * \tabcolsep (6pt) per column
  -- With \textwidth ~ 455pt (letter, 0.75in margins), 12pt/455pt ≈ 0.026
  local padding_per_col = 0.026
  local available = 1.0 - (num_cols * padding_per_col)
  if available < 0.3 then available = 0.3 end

  -- Apply a sqrt-dampening so very long columns don't completely crush short ones
  local weights = {}
  local total_weight = 0
  for i = 1, num_cols do
    local len = max_lengths[i]
    if len < 1 then len = 1 end
    weights[i] = math.sqrt(len)
    total_weight = total_weight + weights[i]
  end

  -- First pass: compute raw proportional widths
  local widths = {}
  local clamped_total = 0
  local unclamped_total = 0
  local clamped = {}
  for i = 1, num_cols do
    widths[i] = (weights[i] / total_weight) * available
    if widths[i] < min_width then
      widths[i] = min_width
      clamped[i] = true
      clamped_total = clamped_total + min_width
    else
      unclamped_total = unclamped_total + widths[i]
    end
  end

  -- Second pass: redistribute to fit exactly in available space
  local remaining = available - clamped_total
  if remaining > 0 and unclamped_total > 0 then
    for i = 1, num_cols do
      if not clamped[i] then
        widths[i] = (widths[i] / unclamped_total) * remaining
      end
    end
  end

  local specs = {}
  for i = 1, num_cols do
    local a = align_prefix(aligns[i])
    local ragged
    if a == "r" then
      ragged = "\\raggedleft\\arraybackslash"
    elseif a == "c" then
      ragged = "\\centering\\arraybackslash"
    else
      ragged = "\\raggedright\\arraybackslash"
    end
    specs[#specs + 1] = string.format(">{%s}p{%.4f\\textwidth}", ragged, widths[i])
  end

  return table.concat(specs, " ")
end

--- Renders a table row (list of cells) to LaTeX.
--- @param cells table List of cell content (each is a list of Blocks)
--- @return string LaTeX row string joined with &
local function render_row(cells)
  local parts = {}
  for _, cell in ipairs(cells) do
    parts[#parts + 1] = blocks_to_latex(cell)
  end
  return table.concat(parts, " & ")
end

--- Main table filter. Replaces Pandoc table with raw LaTeX longtable
--- using proportional column widths.
--- @param tbl table Pandoc Table element
--- @return table Pandoc RawBlock with LaTeX
function Table(tbl)
  local caption = tbl.caption
  local aligns = {}
  local headers = {}
  local body_rows = {}
  local num_cols = 0

  -- Extract column alignments
  for i, colspec in ipairs(tbl.colspecs) do
    aligns[i] = colspec[1] or "AlignDefault"
    num_cols = i
  end

  if num_cols == 0 then return nil end

  -- Extract header cells
  if tbl.head and tbl.head.rows then
    for _, row in ipairs(tbl.head.rows) do
      local cells = {}
      for _, cell in ipairs(row.cells) do
        cells[#cells + 1] = cell.contents
      end
      headers[#headers + 1] = cells
    end
  end

  -- Extract body rows
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cells = {}
      for _, cell in ipairs(row.cells) do
        cells[#cells + 1] = cell.contents
      end
      body_rows[#body_rows + 1] = cells
    end
  end

  -- Measure max content length per column
  local max_lengths = {}
  for i = 1, num_cols do
    max_lengths[i] = 0
  end

  for _, row in ipairs(headers) do
    for i, cell in ipairs(row) do
      local len = content_length(cell)
      if len > max_lengths[i] then max_lengths[i] = len end
    end
  end

  for _, row in ipairs(body_rows) do
    for i, cell in ipairs(row) do
      local len = content_length(cell)
      if len > max_lengths[i] then max_lengths[i] = len end
    end
  end

  -- Build LaTeX
  local colspec = build_colspec(max_lengths, aligns, num_cols)
  local lines = {}

  lines[#lines + 1] = string.format("\\begin{longtable}[]{@{}%s@{}}", colspec)
  lines[#lines + 1] = "\\toprule"

  -- Header rows
  for _, row in ipairs(headers) do
    local parts = {}
    for _, cell in ipairs(row) do
      parts[#parts + 1] = "\\textbf{" .. blocks_to_latex(cell) .. "}"
    end
    lines[#lines + 1] = table.concat(parts, " & ") .. " \\\\"
  end

  if #headers > 0 then
    lines[#lines + 1] = "\\midrule"
    lines[#lines + 1] = "\\endhead"
  end

  -- Body rows
  for _, row in ipairs(body_rows) do
    lines[#lines + 1] = render_row(row) .. " \\\\"
  end

  lines[#lines + 1] = "\\bottomrule"
  lines[#lines + 1] = "\\end{longtable}"

  return pandoc.RawBlock("latex", table.concat(lines, "\n"))
end
