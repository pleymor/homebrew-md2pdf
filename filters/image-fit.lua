--[[
  Pandoc Lua filter (docx only) that caps image display size so tall
  Mermaid diagrams fit on a page. Reads the PNG header for the real
  pixel size, converts at 72 dpi (what the docx writer uses for images
  without density metadata, like mermaid-cli PNGs), and only shrinks
  images exceeding the page box (aspect ratio preserved).
]]

local MAX_W_CM = 16.0 -- A4 content width with 2.5cm margins
local MAX_H_CM = 18.0 -- leaves room for a caption on an A4 page
local DPI = 72
local CM_PER_INCH = 2.54

---Reads a big-endian 32-bit integer from a binary string.
---@param s string Binary data
---@param i number 1-based offset
---@return number Decoded integer
local function be32(s, i)
  local b1, b2, b3, b4 = s:byte(i, i + 3)
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local B64_INDEX = {}
do
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, #alphabet do
    B64_INDEX[alphabet:sub(i, i)] = i - 1
  end
end

---Decodes a base64 string (without padding handling — enough for a prefix).
---@param s string Base64 data
---@return string Decoded bytes
local function b64_decode(s)
  local bytes = {}
  for i = 1, #s - 3, 4 do
    local a = B64_INDEX[s:sub(i, i)]
    local b = B64_INDEX[s:sub(i + 1, i + 1)]
    local c = B64_INDEX[s:sub(i + 2, i + 2)]
    local d = B64_INDEX[s:sub(i + 3, i + 3)]
    if not (a and b and c and d) then
      break
    end
    local n = ((a * 64 + b) * 64 + c) * 64 + d
    bytes[#bytes + 1] = string.char(math.floor(n / 65536) % 256)
    bytes[#bytes + 1] = string.char(math.floor(n / 256) % 256)
    bytes[#bytes + 1] = string.char(n % 256)
  end
  return table.concat(bytes)
end

---Returns the first 24 bytes of a PNG, from a file path or a data URI
---(mermaid-filter embeds diagrams as base64 data URIs).
---@param src string Image source
---@return string|nil PNG header bytes
local function png_header(src)
  local b64 = src:match("^data:image/png;base64,(.+)$")
  if b64 then
    return b64_decode(b64:sub(1, 32))
  end
  local f = io.open(src, "rb")
  if not f then
    return nil
  end
  local header = f:read(24)
  f:close()
  return header
end

---Returns the pixel dimensions of a PNG source, or nil if unreadable.
---@param src string File path or data URI
---@return number|nil width
---@return number|nil height
local function png_size(src)
  local header = png_header(src)
  if not header or #header < 24 or header:sub(13, 16) ~= "IHDR" then
    return nil
  end
  return be32(header, 17), be32(header, 21)
end

---Shrinks oversized images to fit the page box.
---@param img table Pandoc Image
---@return table|nil Modified Image, or nil to keep it unchanged
function Image(img)
  if FORMAT ~= "docx" then
    return nil
  end
  -- Respect explicit sizing (e.g. the title page logo)
  if img.attributes.width or img.attributes.height then
    return nil
  end

  local w_px, h_px = png_size(img.src)
  if not w_px or w_px == 0 or h_px == 0 then
    return nil
  end

  local w_cm = w_px / DPI * CM_PER_INCH
  local h_cm = h_px / DPI * CM_PER_INCH
  if w_cm <= MAX_W_CM and h_cm <= MAX_H_CM then
    return nil
  end

  local scale = math.min(MAX_W_CM / w_cm, MAX_H_CM / h_cm)
  img.attributes.width = string.format("%.2fcm", w_cm * scale)
  img.attributes.height = string.format("%.2fcm", h_cm * scale)
  return img
end
