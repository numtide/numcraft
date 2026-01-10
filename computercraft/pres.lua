-- pres.lua
-- Slideshow renderer for HedgeDoc markdown pads on https://pad.ntd.one
-- Usage: pres <padId>
-- Slide delimiter: --- on its own line
-- Speaker notes: lines after ??? are ignored
-- Title: first Markdown heading (# / ##) becomes slide title (centered)
-- Title slide: slide with only a title (or title + small subtitle) is centered

local BASE = "https://pad.ntd.one/"
local MIN_W, MIN_H = 28, 14        -- minimum usable character grid after scaling
local FOOTER_H = 1                 -- footer rows
local TITLE_SPACING = 1            -- blank line after title
local PADDING = 1                  -- horizontal padding on each side
local BULLET = "* "                -- bullet prefix
local CODE_BORDER = true           -- draw box around code blocks

-- ---------- display selection + auto-scaling ----------

local function getMonitor()
  local sides = {"top","bottom","left","right","front","back"}
  for _, s in ipairs(sides) do
    if peripheral.getType(s) == "monitor" then
      return peripheral.wrap(s)
    end
  end
  return nil
end

local disp = getMonitor()

if not disp then
  error("No monitor found. Attach a monitor to use this program.")
end

local function clamp(n, lo, hi) if n < lo then return lo elseif n > hi then return hi else return n end end

local function setBestMonitorScale(mon)
  -- CC:Tweaked monitor scales: 0.5 .. 5.0 in steps of 0.5
  local scales = {5,4.5,4,3.5,3,2.5,2,1.5,1,0.5}

  local best = 0.5
  for _, sc in ipairs(scales) do
    mon.setTextScale(sc)
    local w,h = mon.getSize()
    if w >= MIN_W and h >= MIN_H then
      best = sc
      break -- biggest readable scale that still meets minimum layout
    end
  end
  mon.setTextScale(best)
  return best
end

local normalScale = setBestMonitorScale(disp)

local function setTitleScale(mon)
  -- For title slides, use a larger scale (fewer chars but bigger text)
  -- We only need to fit a short title, so we can use bigger text
  local scales = {5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5}
  local titleMinW, titleMinH = 12, 6  -- title slides need less space
  local best = normalScale
  for _, sc in ipairs(scales) do
    mon.setTextScale(sc)
    local w, h = mon.getSize()
    if w >= titleMinW and h >= titleMinH then
      best = sc
      break
    end
  end
  mon.setTextScale(best)
  return best
end

local function setNormalScale(mon)
  mon.setTextScale(normalScale)
end

-- ---------- http + parsing ----------

local function padIdToUrl(id)
  return BASE .. id .. "/download"
end

local function httpGetAll(url)
  local h, err = http.get(url)
  if not h then error("HTTP failed: " .. tostring(err)) end
  local body = h.readAll()
  h.close()
  return body
end

local function splitSlides(md)
  local slides, current = {}, {}
  for line in (md .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%-%-%-%s*$") then
      table.insert(slides, table.concat(current, "\n"))
      current = {}
    else
      table.insert(current, line)
    end
  end
  if #current > 0 then table.insert(slides, table.concat(current, "\n")) end
  -- drop empty slides
  local out = {}
  for _, s in ipairs(slides) do
    if s:match("%S") then table.insert(out, s) end
  end
  return out
end

local function stripSpeakerNotes(md)
  -- Everything after a line that is exactly "???" is ignored
  local out = {}
  for line in (md .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%?%?%?%s*$") then
      break
    end
    table.insert(out, line)
  end
  return table.concat(out, "\n")
end

-- ---------- rendering helpers ----------

local function clear()
  disp.setBackgroundColor(colors.black)
  disp.setTextColor(colors.white)
  disp.clear()
  disp.setCursorPos(1,1)
end

local function centerText(s, width)
  if #s >= width then return s:sub(1, width) end
  local pad = math.floor((width - #s) / 2)
  return string.rep(" ", pad) .. s
end

local function wrapLine(s, width)
  local out = {}
  s = s:gsub("\t", "  ")

  while #s > width do
    local cut = width
    local sp = s:sub(1, width):match(".*()%s+")
    if sp and sp > 1 then cut = sp - 1 end
    table.insert(out, s:sub(1, cut))
    s = s:sub(cut + 1):gsub("^%s+", "")
  end

  table.insert(out, s)
  return out
end

local function truncate(s, width)
  if #s <= width then return s end
  return s:sub(1, math.max(0, width - 2)) .. ".."
end

-- Colors for markdown formatting
local COLOR_NORMAL = colors.white
local COLOR_BOLD = colors.yellow
local COLOR_ITALIC = colors.lightGray
local COLOR_CODE = colors.cyan

-- Write text with inline markdown formatting as colors
local function writeFormatted(text)
  local i = 1
  local len = #text

  while i <= len do
    -- Check for bold **text**
    local boldStart, boldEnd, boldText = text:find("%*%*(.-)%*%*", i)
    -- Check for italic *text* (but not **)
    local italicStart, italicEnd, italicText = text:find("%*([^%*]-)%*", i)
    -- Check for inline code `text`
    local codeStart, codeEnd, codeText = text:find("`(.-)`", i)

    -- Find the earliest match
    local nextMatch = nil
    local matchType = nil
    local matchText = nil
    local matchEnd = nil

    if boldStart and (not nextMatch or boldStart < nextMatch) then
      nextMatch, matchType, matchText, matchEnd = boldStart, "bold", boldText, boldEnd
    end
    if italicStart and (not nextMatch or italicStart < nextMatch) then
      nextMatch, matchType, matchText, matchEnd = italicStart, "italic", italicText, italicEnd
    end
    if codeStart and (not nextMatch or codeStart < nextMatch) then
      nextMatch, matchType, matchText, matchEnd = codeStart, "code", codeText, codeEnd
    end

    if nextMatch then
      -- Write text before the match in normal color
      if nextMatch > i then
        disp.setTextColor(COLOR_NORMAL)
        disp.write(text:sub(i, nextMatch - 1))
      end
      -- Write the matched text in its color
      if matchType == "bold" then
        disp.setTextColor(COLOR_BOLD)
      elseif matchType == "italic" then
        disp.setTextColor(COLOR_ITALIC)
      elseif matchType == "code" then
        disp.setTextColor(COLOR_CODE)
      end
      disp.write(matchText)
      disp.setTextColor(COLOR_NORMAL)
      i = matchEnd + 1
    else
      -- No more matches, write the rest
      disp.setTextColor(COLOR_NORMAL)
      disp.write(text:sub(i))
      break
    end
  end
end

-- Parse slide: extract title + body blocks, render with presentation rules
local function renderSlideToLines(md, width)
  md = stripSpeakerNotes(md)

  local lines = {}
  local title, titleLevel
  local bodyLines = {}

  local inCode = false
  local codeLines = {}

  local function flushCode()
    if #codeLines == 0 then return end
    if CODE_BORDER and width >= 4 then
      table.insert(bodyLines, "+" .. string.rep("-", width - 2) .. "+")
      for _, cl in ipairs(codeLines) do
        local inner = cl
        if #inner > width - 4 then inner = inner:sub(1, width - 4) end
        table.insert(bodyLines, "| " .. inner .. string.rep(" ", (width - 4) - #inner) .. " |")
      end
      table.insert(bodyLines, "+" .. string.rep("-", width - 2) .. "+")
    else
      for _, cl in ipairs(codeLines) do
        table.insert(bodyLines, truncate(cl, width))
      end
    end
    codeLines = {}
  end

  local rawLines = {}
  for line in (md .. "\n"):gmatch("([^\n]*)\n") do table.insert(rawLines, line) end

  local i = 1
  while i <= #rawLines do
    local raw = rawLines[i]

    if raw:match("^```") then
      inCode = not inCode
      if not inCode then flushCode() end
      i = i + 1
      goto continue
    end

    if inCode then
      table.insert(codeLines, raw)
      i = i + 1
      goto continue
    end

    -- Title extraction: first heading wins
    if not title then
      local hashes, text = raw:match("^(#+)%s*(.-)%s*$")
      if hashes and text and text ~= "" then
        title = text
        titleLevel = #hashes
        i = i + 1
        goto continue
      end
    end

    -- bullets
    raw = raw:gsub("^%s*[%-%*]%s+", BULLET)

    -- wrap
    for _, w in ipairs(wrapLine(raw, width)) do
      table.insert(bodyLines, w)
    end

    i = i + 1
    ::continue::
  end

  -- Decide if this is a "title slide":
  -- - has a title
  -- - and body is empty or basically 1 short line (subtitle)
  local nonEmptyBody = {}
  for _, l in ipairs(bodyLines) do
    if l:match("%S") then table.insert(nonEmptyBody, l) end
  end

  local isTitleSlide = false
  if title then
    if #nonEmptyBody == 0 then
      isTitleSlide = true
    elseif #nonEmptyBody == 1 and #nonEmptyBody[1] <= math.floor(width * 0.7) then
      isTitleSlide = true
    end
  end

  if isTitleSlide then
    local subtitle = nonEmptyBody[1]
    -- vertical centering happens outside, we just return marked lines
    table.insert(lines, "__TITLE__:" .. title)
    if subtitle then table.insert(lines, "__SUBTITLE__:" .. subtitle) end
    return lines, true
  end

  -- Normal slide: title at top (centered), then body
  if title then
    local t = title
    if titleLevel == 1 then
      t = "= " .. title .. " ="
    end
    table.insert(lines, centerText(truncate(t, width), width))
    for _ = 1, TITLE_SPACING do table.insert(lines, "") end
  end

  for _, bl in ipairs(bodyLines) do
    table.insert(lines, truncate(bl, width))
  end

  return lines, false
end

local function drawFooter(idx, total, width, height)
  disp.setCursorPos(1 + PADDING, height)
  local footer = ("[%d/%d]"):format(idx, total)
  disp.write(footer)
end

local function drawCenteredTitle(lines, idx, total)
  -- Use larger text scale for title slides
  setTitleScale(disp)

  clear()
  local w,h = disp.getSize()
  local usableW = w - 2 * PADDING
  local usableH = h - FOOTER_H

  local title, subtitle
  for _, l in ipairs(lines) do
    title = title or l:match("^__TITLE__:(.*)$")
    subtitle = subtitle or l:match("^__SUBTITLE__:(.*)$")
  end

  local content = {}

  -- Wrap title across multiple lines if needed
  if title then
    local wrappedTitle = wrapLine(title, usableW)
    for _, line in ipairs(wrappedTitle) do
      table.insert(content, centerText(line, usableW))
    end
  end

  if subtitle then
    table.insert(content, "")
    local wrappedSubtitle = wrapLine(subtitle, usableW)
    for _, line in ipairs(wrappedSubtitle) do
      table.insert(content, centerText(line, usableW))
    end
  end

  local startY = math.floor((usableH - #content) / 2) + 1
  startY = clamp(startY, 1, usableH)

  for i, l in ipairs(content) do
    local y = startY + (i - 1)
    if y > usableH then break end
    disp.setCursorPos(1 + PADDING, y)
    writeFormatted(l)
  end

  drawFooter(idx, total, w, h)
end

local function drawNormal(lines, idx, total)
  -- Reset to normal scale for content slides
  setNormalScale(disp)

  clear()
  local w,h = disp.getSize()
  local usableH = h - FOOTER_H

  for i = 1, math.min(#lines, usableH) do
    disp.setCursorPos(1 + PADDING, i)
    writeFormatted(lines[i])
  end

  drawFooter(idx, total, w, h)
end

local function drawSlide(md, idx, total)
  -- First pass: determine if title slide (use normal scale for detection)
  setNormalScale(disp)
  local w = disp.getSize()
  local usableW = w - 2 * PADDING
  local _, isTitleSlide = renderSlideToLines(md, usableW)

  if isTitleSlide then
    -- Re-render at title scale
    setTitleScale(disp)
    w = disp.getSize()
    usableW = w - 2 * PADDING
    local lines = renderSlideToLines(md, usableW)
    drawCenteredTitle(lines, idx, total)
  else
    local lines = renderSlideToLines(md, usableW)
    drawNormal(lines, idx, total)
  end
end

-- ---------- main ----------

local args = {...}
assert(args[1], "Usage: pres <padId>")
assert(http, "HTTP is disabled. Enable http in CC:Tweaked config (http.enable=true).")

local padId = args[1]
local url = padIdToUrl(padId)

local ok, mdOrErr = pcall(httpGetAll, url)
if not ok then
  error("Could not fetch pad '" .. padId .. "'. URL: " .. url .. "\n" .. tostring(mdOrErr))
end

local slides = splitSlides(mdOrErr)
if #slides == 0 then error("No slides found. Add '---' separators or ensure pad has content.") end

-- Show controls in console
print("Loaded " .. #slides .. " slides from: " .. padId)
print("")
print("Controls:")
print("  Next:  Right / D / Space")
print("  Prev:  Left / A / Backspace")
print("  Quit:  Q")
print("  Touch: left half = prev, right half = next")
print("")

local function showProgress(idx, total)
  local _, y = term.getCursorPos()
  term.setCursorPos(1, y)
  term.clearLine()
  term.write(string.format("Slide %d/%d", idx, total))
end

local i = 1
drawSlide(slides[i], i, #slides)
showProgress(i, #slides)

while true do
  local e, p1, p2, p3 = os.pullEvent()

  if e == "key" then
    if p1 == keys.q then break end

    if p1 == keys.right or p1 == keys.d or p1 == keys.space then
      if i < #slides then i = i + 1 end
      drawSlide(slides[i], i, #slides)
      showProgress(i, #slides)

    elseif p1 == keys.left or p1 == keys.a or p1 == keys.backspace then
      if i > 1 then i = i - 1 end
      drawSlide(slides[i], i, #slides)
      showProgress(i, #slides)

    end

  elseif e == "monitor_touch" then
    -- monitor_touch event: (event, side, x, y)
    -- p1 = side, p2 = x, p3 = y
    local w, _ = disp.getSize()
    if p2 <= w / 2 then
      -- tap left half = previous
      if i > 1 then i = i - 1 end
    else
      -- tap right half = next
      if i < #slides then i = i + 1 end
    end
    drawSlide(slides[i], i, #slides)
    showProgress(i, #slides)
  end
end

clear()
print("\nBye")
