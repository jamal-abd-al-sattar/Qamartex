----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
	-- helpers: detect Eastern Arabic-Indic digits and ASCII comma only
	function is_eastern_digit(cp)
		return cp >= 0x0660 and cp <= 0x0669
	end
	function is_arabic_decimal_seperator(cp)
		return cp == 0x066B -- ',' ASCII comma
	end
	
	function is_arabic_thousands_seperator(cp)
		return cp == 0x066C 
	end
	
	-- reverse contiguous runs of digits+ASCII-commas
	function reverse_digit_sequences(s)
		local out = {}
		local buf = {} -- buffer for matched run (each element is a UTF-8 character string)
	
		for _, cp in utf8.codes(s) do
			if is_eastern_digit(cp) or is_arabic_decimal_seperator(cp) or is_arabic_thousands_seperator(cp) then
				-- accumulate into buffer
				buf[#buf + 1] = utf8.char(cp)
			else
				-- non-matching char: flush buffer reversed, then append current char
				if #buf > 0 then
					for i = #buf, 1, -1 do
						out[#out + 1] = buf[i]
					end
					buf = {}
				end
				out[#out + 1] = utf8.char(cp)
			end
		end
	
		-- flush trailing buffer
		if #buf > 0 then
			for i = #buf, 1, -1 do
				out[#out + 1] = buf[i]
			end
		end
	
		return table.concat(out)
	end
	
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
-- First, the updated UTF-8 safe arabic_to_western_number function (from before)

function arabic_to_western_number(s)
    local arabic_to_western = {
        ['٠'] = '0',
        ['١'] = '1',
        ['٢'] = '2',
        ['٣'] = '3',
        ['٤'] = '4',
        ['٥'] = '5',
        ['٦'] = '6',
        ['٧'] = '7',
        ['٨'] = '8',
        ['٩'] = '9',
        -- Optionally: ['٫'] = '.',  -- Arabic decimal point to .
    }
    
    local result = {}
    local i = 1
    local len = #s
    local prev_was_digit = false
    
    while i <= len do
        local start = i
        local c1 = s:byte(i)
        
        if c1 == nil then break end
        
        if c1 < 128 then
            i = i + 1  -- 1-byte
        elseif c1 >= 192 and c1 < 224 then
            i = i + 2  -- 2-byte
        elseif c1 >= 224 and c1 < 240 then
            i = i + 3  -- 3-byte
        elseif c1 >= 240 and c1 < 248 then
            i = i + 4  -- 4-byte
        else
            i = i + 1  -- invalid, skip
        end
        
        local char = s:sub(start, i - 1)
        
        local replacement = arabic_to_western[char]
        if replacement then
            table.insert(result, replacement)
            prev_was_digit = true
        else
            if char == '٫' then
                local is_adjacent = prev_was_digit
                
                if not is_adjacent and i <= len then
                    -- Peek next
                    local next_start = i
                    local next_c1 = s:byte(i)
                    local next_len = 1
                    if next_c1 >= 192 and next_c1 < 224 then next_len = 2
                    elseif next_c1 >= 224 and next_c1 < 240 then next_len = 3
                    elseif next_c1 >= 240 and next_c1 < 248 then next_len = 4
                    end
                    local next_char = s:sub(next_start, next_start + next_len - 1)
                    if arabic_to_western[next_char] then
                        is_adjacent = true
                    end
                end
                
                if is_adjacent then
                    table.insert(result, '.')
                else
                    table.insert(result, '٫')
                end
                prev_was_digit = false
            else
                table.insert(result, char)
                prev_was_digit = false
            end
        end
    end
    return table.concat(result)
end
----------------------------------------------------------------------------------------------------------------------------------------------
-- Main function: convert Arabic units and numbers to Western format
 function arabic_to_western_unit(s)
    local units_map = {
        ['سم']    = 'cm',
        ['مم']    = 'mm',
        ['نقطة']  = 'pt',
        ['بقعة']  = 'bp',
        ['إنش']   = 'in',
        ['بيكا']  = 'pc',
        ['ديدو']  = 'dd',
        ['سيسرو'] = 'cc',
        ['خاصة']  = 'sp',
        ['إم']    = 'em',
        ['إكس']   = 'ex',
    }
    
    -- ٪ (U+066A) = UTF-8 D9 AA
    local PERCENT  = '\xD9\xAA'           -- Single ٪
    local PERCENT2 = '\xD9\xAA\xD9\xAA'   -- Double ٪٪
    
    local arabic_digits_set = {}
    for _, d in ipairs({'٠','١','٢','٣','٤','٥','٦','٧','٨','٩'}) do
        arabic_digits_set[d] = true
    end
    
    local function char_width(b)
        if    b >= 240 and b < 248 then return 4
        elseif b >= 224 and b < 240 then return 3
        elseif b >= 192 and b < 224 then return 2
        else                             return 1
        end
    end
    
    local function sp_to_pt_str(sp)
        local str = string.format("%.5f", sp / 65536)
        str = str:gsub('0+$', ''):gsub('%.$', '.0')
        return str .. 'pt'
    end
    
    local result = {}
    local i      = 1
    local len    = #s
    
    while i <= len do
        local c1   = s:byte(i)
        if c1 == nil then break end
        local cw   = char_width(c1)
        local char = s:sub(i, i + cw - 1)
        i = i + cw
        
        if not arabic_digits_set[char] then
            -- Not an Arabic digit: emit as-is
            table.insert(result, char)
        else
            -- Collect digit run: Arabic digits + ٫ + ,
            local number_buf = { char }
            while i <= len do
                local nc  = s:byte(i)
                local nw  = char_width(nc)
                local nch = s:sub(i, i + nw - 1)
                if arabic_digits_set[nch] or nch == '٫' or nch == ',' then
                    table.insert(number_buf, nch)
                    i = i + nw
                else
                    break
                end
            end
            
            local unit_start = i
            local number_str = table.concat(number_buf)
            local western_num = arabic_to_western_number(number_str)
            local pct_val = tonumber(western_num)
            
            -- ٪٪ → % of \vsize (must check before single ٪)
            if s:sub(unit_start, unit_start + #PERCENT2 - 1) == PERCENT2 then
                i = unit_start + #PERCENT2
                if pct_val and tex and tex.vsize then
                    table.insert(result, sp_to_pt_str(pct_val / 100 * tex.vsize))
                else
                    table.insert(result, western_num .. '%%')
                end
            -- ٪ → % of \hsize
            elseif s:sub(unit_start, unit_start + #PERCENT - 1) == PERCENT then
                i = unit_start + #PERCENT
                if pct_val and tex and tex.hsize then
                    table.insert(result, sp_to_pt_str(pct_val / 100 * tex.hsize))
                else
                    table.insert(result, western_num .. '%')
                end
            else
                -- Named units
                local found = false
                for unit_ar, unit_en in pairs(units_map) do
                    local ubytes = #unit_ar
                    if s:sub(unit_start, unit_start + ubytes - 1) == unit_ar then
                        i = unit_start + ubytes
                        table.insert(result, western_num)
                        table.insert(result, unit_en)
                        found = true
                        break
                    end
                end
                if not found then
                    -- Bare number, no recognised unit: emit converted number
                    table.insert(result, western_num)
                    i = unit_start
                end
            end
        end -- else
    end -- while
    
    return table.concat(result)
end
----------------------------------------------------------------------------------------------------------------------------------------------
function number_to_eastern_arabic(n)
    local digits = {"٠","١","٢","٣","٤","٥","٦","٧","٨","٩"}
    local s = tostring(n)
    local out = ""
    for c in s:gmatch"." do
        out = out .. digits[tonumber(c)+1]
    end
    return (out)
end

function reversed_number_to_eastern_arabic(n)
    local digits = {"٠","١","٢","٣","٤","٥","٦","٧","٨","٩"}
    local s = tostring(n)
    local out = ""
    for c in s:gmatch"." do
        out = digits[tonumber(c)+1] .. out
    end
    return (out)
end
----------------------------------------------------------------------------------------------------------------------------------------------
function number_to_abjadi(n)
  local abjadi_map = {
    {1000, "غ"},
    {900, "ظ"},
    {800, "ض"},
    {700, "ذ"},
    {600, "خ"},
    {500, "ث"},
    {400, "ت"},
    {300, "ش"},
    {200, "ر"},
    {100, "ق"},
    {90, "ص"},
    {80, "ف"},
    {70, "ع"},
    {60, "س"},
    {50, "ن"},
    {40, "م"},
    {30, "ل"},
    {20, "ك"},
    {10, "ي"},
    {9, "ط"},
    {8, "ح"},
    {7, "ز"},
    {6, "و"},
    {5, "ه"},
    {4, "د"},
    {3, "ج"},
    {2, "ب"},
    {1, "أ"},
  }
  local out = ""
  for _, pair in ipairs(abjadi_map) do
    local val, char = pair[1], pair[2]
    while n >= val do
      out = out .. char
      n = n - val
    end
  end
  return out
end
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
local function utf8_to_atoms(s)
    local chars = {}
    local i = 1
    local len = #s

    local function is_ascii_alpha(b)
        return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
    end

    while i <= len do
        local c1 = s:byte(i)

        if c1 == 92 then  -- backslash '\'
            local next = s:byte(i + 1)
            if next and is_ascii_alpha(next) then
                -- word command like \langle \vrule
                local j = i + 1
                while j <= len and is_ascii_alpha(s:byte(j)) do
                    j = j + 1
                end
                table.insert(chars, s:sub(i, j - 1))
                -- skip trailing space if any
                if s:byte(j) == 32 then j = j + 1 end
                i = j
            else
                -- single char command like \{ \} \| \,
                table.insert(chars, s:sub(i, i + 1))
                i = i + 2
            end

        elseif c1 == 32 then  -- skip plain spaces
            i = i + 1

        else
            -- UTF-8 character
            local char_len = 1
            if c1 >= 192 and c1 < 224 then
                char_len = 2
            elseif c1 >= 224 and c1 < 240 then
                char_len = 3
            elseif c1 >= 240 and c1 < 248 then
                char_len = 4
            end
            table.insert(chars, s:sub(i, i + char_len - 1))
            i = i + char_len
        end
    end

    return chars
end

local left_braces = {
    ["("]  = [=[\left(]=],
    [")"]  = [=[\left)]=],
    ["["]  = [=[\left[]=],
    ["]"]  = [=[\left]]=],
    ["\\{"]  = [=[\left\{]=],
    ["\\}"]  = [=[\left\}]=],
    ["<"]  = [=[\left\langle]=],
    [">"]  = [=[\left\rangle]=],
    ["\\|"]  = [=[\left\|]=],  -- double bar
    ["/"]  = [=[\left/]=],
    ["\\"] = [=[\left\backslash]=],
}

local right_braces = {
    ["("]  = [=[\right(]=],
    [")"]  = [=[\right)]=],
    ["["]  = [=[\right[]=],
    ["]"]  = [=[\right]]=],
    ["\\{"]  = [=[\right\{]=],
    ["\\}"]  = [=[\right\}]=],
    ["<"]  = [=[\right\rangle]=],
    [">"]  = [=[\right\rangle]=],
    ["\\|"]  = [=[\right\|]=],
    ["/"]  = [=[\right/]=],
    ["\\"] = [=[\right\backslash]=],
}
function process_equations(display_mode, template_row, content_row)
    local chars = utf8_to_atoms(template_row)
    local len = #chars

    local result = {}
	local rightdel =""
	local leftdel =""
    for i, char in ipairs(chars) do
        local first = (i == 1)
        local last  = (i == len)
	if left_braces[char] then
        if first then
            leftdel = left_braces[char]
        elseif last then
            rightdel = right_braces[char]
        else
            -- middle brace, just insert as-is or handle as vrule
            table.insert(result, char)
        end
        elseif char == "ي" then
            if first then
                table.insert(result, [=[$#$\hfil\hskip 2pt]=])
            elseif last then
                table.insert(result, [=[&\hskip 2pt$#$\hfil]=])
            else
                table.insert(result, [=[&\hskip 2pt$#$\hfil\hskip 2pt]=])
            end
        elseif char == "ش" then
            if first then
                table.insert(result, [=[\hfil$#$\hskip 2pt]=])
            elseif last then
                table.insert(result, [=[&\hskip 2pt\hfil$#$]=])
            else
                table.insert(result, [=[&\hskip 2pt\hfil$#$\hskip 2pt]=])
            end
        elseif char == "و" then
            if first then
                table.insert(result, [=[\hfil$#$\hfil\hskip 2pt]=])
            elseif last then
                table.insert(result, [=[&\hskip 2pt\hfil$#$\hfil]=])
            else
                table.insert(result, [=[&\hskip 2pt\hfil$#$\hfil\hskip 2pt]=])
            end
        elseif char == "|" then
            table.insert(result, [=[\vrule]=])
        else
            table.insert(result, char)
        end
    end
	
if leftdel == "" and rightdel ~= "" then
    leftdel = "\\left."
end
if leftdel ~= "" and rightdel == "" then
    rightdel = "\\right."
end
    local res = table.concat(result)
    res = res:gsub([=[^\vrule&]=], [=[\vrule]=])   -- at start of string
    res = res:gsub("%$#%$", "\\padcell{$" .. display_mode .. "#$}")
    local output = leftdel..[=[\vcenter{\offinterlineskip\halign{]=]
    output = output .. res .. [=[\cr]=] .. content_row .. [=[}}]=]..rightdel
    return output
end


function process_numbered_equations(display_mode, template_row, content_row)
    local chars = utf8_to_atoms(template_row)
    local len = #chars
    local result = {}
	local rightdel =""
	local leftdel =""
    for i, char in ipairs(chars) do
        local first = (i == 1)
        local last  = (i == len)

        if left_braces[char] then
        if first then
            leftdel = left_braces[char]
        elseif last then
            rightdel = right_braces[char]
        else
            -- middle brace, just insert as-is or handle as vrule
            table.insert(result, char)
        end
        elseif char == "ي" then
            if first then
                table.insert(result, [=[\rlap{$#$}\tabskip=0ptplus1fil]=])
            elseif last then
                table.insert(result, [=[\tabskip=0ptplus1fil&\rlap{$#$}]=])
            else
                table.insert(result, [=[\tabskip=0pt&\hskip2pt$#$\hfil\hskip 2pt]=])
            end
        elseif char == "ش" then
            if first then
                table.insert(result, [=[\llap{$#$}\tabskip=0ptplus1fil]=])
            elseif last then
                table.insert(result, [=[\tabskip=0ptplus1fil&\llap{$#$}]=])
            else
                table.insert(result, [=[\tabskip=0pt&\hskip2pt\hfil$#$\hskip2pt]=])
            end
        elseif char == "و" then
            if first then
                table.insert(result, [=[\clap{$#$}\tabskip=0ptplus1fil]=])
            elseif last then
                table.insert(result, [=[\tabskip=0ptplus1fil &\clap{$#$}]=])
            else
                table.insert(result, [=[\tabskip=0pt&\hskip2pt\hfil$#$\hfil\hskip2pt]=])
            end
        elseif char == "|" then
            table.insert(result, [=[\vrule]=])
        else
            table.insert(result, char)
        end
    end

    local res = table.concat(result)
    res = res:gsub([=[^\vrule&]=], [=[\vrule]=])   -- at start of string
    res = res:gsub([=[\tabskip=0ptplus1fil\tabskip=0pt]=], [=[\tabskip=0ptplus1fil]=])
    res = res:gsub("%$#%$", "\\padcell{$" .. display_mode .. "#$}")
    local output = leftdel..[=[\vcenter{\offinterlineskip\tabskip = 0pt\halign to \hsize{]=]
    output = output .. res .. [=[\tabskip = 0pt\cr]=] .. content_row .. [=[}}]=]..rightdel
    return output
end



function process_table(template_row, content_row)
    local chars = utf8_to_atoms(template_row)
    local len = #chars
    local result = {}
	local rightdel =""
	local leftdel =""
    for i, char in ipairs(chars) do
        local first = (i == 1)
        local last  = (i == len)

        if left_braces[char] then
        if first then
            leftdel = left_braces[char]
        elseif last then
            rightdel = right_braces[char]
        else
            -- middle brace, just insert as-is or handle as vrule
            table.insert(result, char)
        end
        elseif char == "ي" then
            if first then
                table.insert(result, [=[#\hfil\hskip 4pt minus 2pt]=])
            elseif last then
                table.insert(result, [=[&\hskip 4pt minus 2pt#\hfil]=])
            else
                table.insert(result, [=[&\hskip 4pt minus 2pt#\hfil\hskip 4pt minus 2pt]=])
            end
        elseif char == "ش" then
            if first then
                table.insert(result, [=[\hfil#\hskip 4pt minus 2pt]=])
            elseif last then
                table.insert(result, [=[&\hskip 4pt minus 2pt\hfil#]=])
            else
                table.insert(result, [=[&\hskip 4pt minus 2pt\hfil#\hskip 4pt minus 2pt]=])
            end
        elseif char == "و" then
            if first then
                table.insert(result, [=[\hfil#\hfil\hskip 4pt minus 2pt]=])
            elseif last then
                table.insert(result, [=[&\hskip 4pt minus 2pt\hfil#\hfil]=])
            else
                table.insert(result, [=[&\hskip 4pt minus 2pt\hfil#\hfil\hskip 4pt minus 2pt]=])
            end
        elseif char == "|" then
            table.insert(result, [=[\vrule]=])
        else
            table.insert(result, char)
        end
    end

    local res = table.concat(result)
    res = res:gsub([=[^\vrule&]=], [=[\vrule]=])   -- at start of string
    res = res:gsub("#", "\\padcell{#}")
    local output = leftdel..[=[\vcenter{\offinterlineskip\halign{]=]
    output = output .. res .. [=[\cr]=] .. content_row .. [=[}}]=]..rightdel
    return output
end

function process_wide_table(input1, input2)
    local chars = utf8_to_atoms(input1)
    local len = #chars
    local result = {}
    local rightdel =""
	local leftdel =""
    local columns_nums = 0

    for i, char in ipairs(chars) do
        local first = (i == 1)
        local last  = (i == len)

        if left_braces[char] then
        if first then
            leftdel = left_braces[char]
        elseif last then
            rightdel = right_braces[char]
        else
            -- middle brace, just insert as-is or handle as vrule
            table.insert(result, char)
        end
        elseif char == "ي" then
            if first then
                table.insert(result, [=[\hbox to \colwidth{#\hfil\hskip 4pt minus 2pt}&]=])
            elseif last then
                table.insert(result, [=[\hbox to \colwidth{\hskip 4pt minus 2pt#\hfil}&]=])
            else
                table.insert(result, [=[\hbox to \colwidth{\hskip 4pt minus 2pt#\hfil\hskip 4pt minus 2pt}&]=])
            end
            columns_nums = columns_nums + 1
        elseif char == "ش" then
            if first then
                table.insert(result, [=[\hbox to \colwidth{\hfil#\hskip 4pt minus 2pt}&]=])
            elseif last then
                table.insert(result, [=[\hbox to \colwidth{\hskip 4pt minus 2pt\hfil#}&]=])
            else
                table.insert(result, [=[\hbox to \colwidth{\hskip 4pt minus 2pt\hfil#\hskip 4pt minus 2pt}&]=])
            end
            columns_nums = columns_nums + 1
        elseif char == "و" then
            if first then
                table.insert(result, [=[\hbox to \colwidth{\hfil#\hfil\hskip 4pt minus 2pt}&]=])
            elseif last then
                table.insert(result, [=[\hbox to \colwidth{\hskip 4pt minus 2pt\hfil#\hfil}&]=])
            else
                table.insert(result, [=[\hbox to \colwidth{\hskip 4pt minus 2pt\hfil#\hfil\hskip 4pt minus 2pt}&]=])
            end
            columns_nums = columns_nums + 1
        elseif char == "|" then
            table.insert(result, [=[\vrule]=])
        else
            table.insert(result, char)
        end
    end

    local res = table.concat(result)
    res = res:gsub([=[^\vrule&]=], [=[\vrule]=])   -- at start of string
    if res:sub(-1) == "&" then
        res = res:sub(1, -2)
    end
    res = res:gsub("#", "\\padcell{#}")
    local output = leftdel..[=[\newdimen\colwidth \colwidth=\hsize \divide\colwidth by]=] .. tostring(columns_nums)
    output = output .. [=[\vcenter{\offinterlineskip\halign to \hsize{]=]
    output = output .. res .. [=[\cr]=] .. input2 .. [=[}}]=]..rightdel
    return output
end
----------------------------------------------------------------------------------------------------------------------------------------------
function process_image(w_param, h_param, s_param, file_name)
  -- Create and scan the image
  local img_obj = img.new({ filename = file_name })
  img_obj = img.scan(img_obj)
  
  -- Get natural dimensions in scaled points (sp)
  local natural_width = img_obj.width or img_obj.xsize
  local natural_height = img_obj.height or img_obj.ysize
  
  -- Debug: print natural dimensions
  --texio.write_nl("Natural: " .. natural_width .. " x " .. natural_height .. " sp")
  
  -- Initialize target dimensions with natural size
  local target_w = natural_width
  local target_h = natural_height
  
  -- Helper function to convert TeX dimensions
  local function to_sp(v)
    if not v or v == '' or v == '0' then return nil end
    -- Try as a number first
    local n = tonumber(v)
    if n then
      -- If it's a plain number, assume it's in points and convert to sp
      if string.match(v, "^[0-9%.]*$") then
        return n * 65536  -- Convert pt to sp (1 pt = 65536 sp)
      else
        return n  -- Already in sp if it's just a number
      end
    end
    -- Try as a TeX dimension
    local ok, sp = pcall(tex.sp, v)
    if ok then
      return sp
    end
    return nil
  end
  
  -- Apply SCALE parameter FIRST (this was the main issue)
  -- Scale should multiply the natural dimensions
  if s_param and s_param ~= '' and s_param ~= '0' then
    local sf = tonumber(s_param)
    if sf and sf > 0 then
      --texio.write_nl("Applying scale: " .. sf)
      target_w = natural_width * sf
      target_h = natural_height * sf
    end
  end
  
  -- Apply WIDTH parameter (if provided)
  if w_param and w_param ~= '' and w_param ~= '0' then
    local w_sp = to_sp(w_param)
    if w_sp and w_sp > 0 then
      -- Calculate scaling factor based on width
      local scale_factor = w_sp / natural_width
      target_w = w_sp
      target_h = natural_height * scale_factor
    end
  end
  
  -- Apply HEIGHT parameter (if provided)
  if h_param and h_param ~= '' and h_param ~= '0' then
    local h_sp = to_sp(h_param)
    if h_sp and h_sp > 0 then
      -- Calculate scaling factor based on height
      local scale_factor = h_sp / natural_height
      target_h = h_sp
      -- Only adjust width if width wasn't explicitly set
      if not (w_param and w_param ~= '' and w_param ~= '0') then
        target_w = natural_width * scale_factor
      end
    end
  end
  
  -- Debug: print target dimensions
  --texio.write_nl("Target: " .. target_w .. " x " .. target_h .. " sp")
  
  -- Set the dimensions on the image object
  img_obj.width = target_w
  img_obj.height = target_h
  
  -- Write to PDF
  return img.write(img_obj)
end


----------------------------------------------------------------------------------------------------------------------------------------------
  toc_file = nil
  function toc_open_for_overwrite()
    toc_file = io.open("الفهرس.tex","w")
    if not toc_file then
      texio.write_nl("log", "خطأ: ملف الحتويات غير موجود")
    end
  end
  
  function toc_write(title, pageno)
    if toc_file then
    	local toc_string = [=[\hbox to \hsize{]=] .. title .. [=[\quad ]=] .. pageno .. "}\n"
    	toc_string = reverse_digit_sequences(toc_string)
      toc_file:write(toc_string)
    end
  end
  
  function toc_close()
    if toc_file then toc_file:close(); toc_file = nil end
  end




---------------------------------------------------------------------------------------------------------------------------------------------- 
function make_title()
    local f = io.open("الفهرس.tex", "r")
    if f then
      f:close()
      tex.print([=[\input{الفهرس.tex}}]=])
    end
   toc_open_for_overwrite()
end

----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
function arabic_scale_box(input1, input2, input3)
    local converted1 = arabic_to_western_number(reverse_digit_sequences(input1))
    local converted2 = arabic_to_western_number(reverse_digit_sequences(input2))
    return [=[\scalebox{]=] .. converted1  .. '}{' .. converted2 .. '}{' .. input3 .. '}'
 end


function cancel()
local w = tex.box[0].width  / 65781.76
local h = tex.box[0].height / 65781.76
local d = tex.box[0].depth  / 65781.76
tex.sprint(string.format("q 0.5 w 0 %g m %g %g l S Q", -d, w, h))
end
----------------------------------------------------------------------------------------------------------------------------------------------
-------------------------comment: lain LuaTeX Counter Management System-----------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
current_counter_name= ""
current_counter_parent= ""
counter_deps = {}
-------------------------
function create_counter(name, parent)
		if parent ~= ""   then
		 	counter_deps[current_counter_name] = parent or "none"
		 end
    	tex.sprint("\\newcount\\" .. current_counter_name)
    	tex.sprint("\\" .. current_counter_name .. "=0")
end
-------------------------
function reset_dependent_counters(parent_name)
    for name, parent in pairs(counter_deps) do
        if parent == parent_name then
            tex.sprint("\\" .. name .. "=0")
        end
    end
end
-------------------------
styles={}
counters={}
function create_statement(name, style, counter)
    if styles[name] then
        tex.error("العبارة " .. name .. " معرفة مسبقًا")
        return
    end
    styles[name]=style or "none"
    counters[name]=counter or "none"
end

function increment_statement_counter(name)
    if not counters[name] then
        tex.error("العبارة " .. name .. " ليس لها عداد")
        return
    end 
    tex.sprint("\\advance\\"..counters[name].. " by 1")
end

function print_statement(name)
    if not styles[name] then
        tex.error("العبارة " .. name .. " لم تُعرف")
        return
    end
    return (name .. styles[name])
end

----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
  local arabic_math_map = {
  {"أ", "𞸀"},
    {"بـ", "𞸡"},
  {"ب", "𞸁"},
  {"جـ", "𞸢"},
  {"ج", "𞸂"},
  {"د", "𞸃"},
  {"ه", "𞸤"},
  {"و", "𞸅"},
  {"ز", "𞸆"},
  {"حـ", "𞸧"},
  {"ح", "𞸇"},
  {"ط", "𞸈"},
  {"ي", "𞸉"},
  {"ك", "𞸊"},
  {"ل", "𞸋"},
  {"م", "𞸌"},
  {"ن", "𞸍"},
  {"س", "𞸎"},
  {"ع", "𞸏"},
  {"ف", "𞸐"},
  {"ص", "𞸑"},
  {"ق", "𞸒"},
  {"ر", "𞸓"},
  {"ش", "𞸔"},
  {"ت", "𞸕"},
  {"ث", "𞸖"},
  {"خـ", "𞸷"},
  {"خ", "𞸗"},
  {"ذ", "𞸘"},
  {"ض", "𞸙"},
  {"ظ", "𞸚"},
  {"غ", "𞸛"},
}

function arabic_math_chars(s)
  for _, pair in ipairs(arabic_math_map) do
    s = s:gsub(pair[1], pair[2])
  end
  return s
end




local arabic_mathematical_map = {
  {"أ", "{\\Alef}"},
  {"ب", "{\\Ba}"},
  {"ج", "{\\Jeem}"},
  {"د", "{\\Dal}"},
  {"ه", "{\\Ha}"},
  {"و", "{\\Waw}"},
  {"ز", "{\\Za}"},
  {"ح", "{\\HHa}"},
  {"ط", "{\\TTaa}"},
  {"ي", "{\\Ya}"},
  {"ك", "{\\Kaf}"},
  {"ل", "{\\Lam}"},
  {"م", "{\\Meem}"},
  {"ن", "{\\Noon}"},
  {"س", "{\\Seen}"},
  {"ع", "{\\Ayn}"},
  {"ف", "{\\Fa}"},
  {"ص", "{\\Sad}"},
  {"ق", "{\\Qaf}"},
  {"ر", "{\\Ra}"},
  {"ش", "{\\Sheen}"},
  {"ت", "{\\Ta}"},
  {"ث", "{\\Tha}"},
  {"خ", "{\\Kha}"},
  {"ذ", "{\\Dhal}"},
  {"ض", "{\\Dad}"},
  {"ظ", "{\\Zzaa}"},
  {"غ", "{\\Ghain}"},
}

function arabic_mathematical_chars(s)
  for _, pair in ipairs(arabic_mathematical_map) do
    s = s:gsub(pair[1], pair[2])
  end
  return s
end

local arabic_mathematical_looped_map = {
  {"أ", "{\\loopedAlef}"},
  {"ب", "{\\loopedBa}"},
  {"ج", "{\\loopedJeem}"},
  {"د", "{\\loopedDal}"},
  {"ه", "{\\loopedHa}"},
  {"و", "{\\loopedWaw}"},
  {"ز", "{\\loopedZa}"},
  {"ح", "{\\loopedHHa}"},
  {"ط", "{\\loopedTTaa}"},
  {"ي", "{\\loopedYa}"},
  {"ك", "{\\loopedKaf}"},
  {"ل", "{\\loopedLam}"},
  {"م", "{\\loopedMeem}"},
  {"ن", "{\\loopedNoon}"},
  {"س", "{\\loopedSeen}"},
  {"ع", "{\\loopedAyn}"},
  {"ف", "{\\loopedFa}"},
  {"ص", "{\\loopedSad}"},
  {"ق", "{\\loopedQaf}"},
  {"ر", "{\\loopedRa}"},
  {"ش", "{\\loopedSheen}"},
  {"ت", "{\\loopedTa}"},
  {"ث", "{\\loopedTha}"},
  {"خ", "{\\loopedKha}"},
  {"ذ", "{\\loopedDhal}"},
  {"ض", "{\\loopedDad}"},
  {"ظ", "{\\loopedZzaa}"},
  {"غ", "{\\loopedGhain}"},
}

function arabic_mathematical_looped_chars(s)
  for _, pair in ipairs(arabic_mathematical_looped_map) do
    s = s:gsub(pair[1], pair[2])
  end
  return s
end


----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
local fn_pages_ordered = {}
local fn_read = io.open("fn_pages.dat", "r")
if fn_read then
    for line in fn_read:lines() do
        local p = line:match("^(%d+)$")
        if p then table.insert(fn_pages_ordered, tonumber(p)) end
    end
    fn_read:close()
end

fn_per_page = 0

function get_footnote_num(abs_n)
    local this_page = fn_pages_ordered[abs_n]
    local prev_page = fn_pages_ordered[abs_n - 1]
    if abs_n == 1 or (this_page ~= nil and prev_page ~= nil and this_page ~= prev_page) then
        fn_per_page = 0
    end
    fn_per_page = fn_per_page + 1
    return fn_per_page
end

local fn_out = io.open("fn_pages.dat", "w")

function record_fn_page(page_n)
    fn_out:write(page_n .. "\n")
    fn_out:flush()
end
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
