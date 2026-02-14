-- mkdnflow.nvim (Tools for fluent markdown notebook navigation and management)
-- Copyright (C) 2022 Jake W. Vincent <https://github.com/jakewvincent>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- This module: Link management public API

local core = require('mkdnflow.links.core')
local utils = require('mkdnflow.utils')
local Link = core.Link
local LinkPart = core.LinkPart

-- Table for global functions
local M = {}

-- Export classes for advanced use
M.Link = Link
M.LinkPart = LinkPart

-- Export patterns for external use
M.patterns = core.patterns
M.pattern_order = core.pattern_order

-- =============================================================================
-- Backwards-compatible API functions
-- =============================================================================

--- Retrieve the link under the cursor (or at a given column)
---@param col? integer 0-indexed column to check (defaults to cursor position)
---@return Link|nil link The link under the cursor, or nil if none found
M.getLinkUnderCursor = function(col)
    return Link:read(col)
end

--- Extract a specific part (source, name, or anchor) from a Link object or legacy tuple
---@param link_table Link|table|nil The link to extract from
---@param part? 'source'|'name'|'anchor' Which part to extract (defaults to 'source')
---@return string|nil text The extracted text
---@return string|nil anchor The anchor fragment (for 'source' part), or empty string
---@return string|nil link_type The link type
---@return integer|nil start_row
---@return integer|nil start_col
---@return integer|nil end_row
---@return integer|nil end_col
M.getLinkPart = function(link_table, part)
    if not link_table then
        return nil
    end

    part = part or 'source'

    -- Check if this is a Link object or old-style tuple
    local link
    if link_table.__className == 'Link' then
        link = link_table
    else
        -- Convert old tuple to Link object
        table.unpack = table.unpack or unpack
        local match, match_lines, link_type, start_row, start_col, end_row, end_col =
            table.unpack(link_table)
        link = Link:new({
            match = match,
            match_lines = match_lines,
            type = link_type,
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
            valid = true,
        })
    end

    if part == 'source' then
        local source_part = link:get_source()
        return source_part.text,
            source_part.anchor,
            link.type,
            source_part.start_row,
            source_part.start_col,
            source_part.end_row,
            source_part.end_col
    elseif part == 'name' then
        local name_part = link:get_name()
        return name_part.text,
            '',
            link.type,
            name_part.start_row,
            name_part.start_col,
            name_part.end_row,
            name_part.end_col
    elseif part == 'anchor' then
        local anchor_part = link:get_anchor()
        return anchor_part.text,
            '',
            link.type,
            anchor_part.start_row,
            anchor_part.start_col,
            anchor_part.end_row,
            anchor_part.end_col
    end
end

--- Retrieve the attribute or text of a Pandoc bracketed span under the cursor
---@param part? 'attr'|'text' Which part to retrieve (defaults to 'attr')
---@return string|nil result The attribute or text content
---@return integer|nil first Start column of the result
---@return integer|nil last End column of the result
---@return integer|nil row The row of the bracketed span
M.getBracketedSpanPart = function(part)
    -- Use 'attr' as part if no argument provided
    part = part or 'attr'
    -- Get current cursor position
    local position = vim.api.nvim_win_get_cursor(0)
    local row, col = position[1], position[2]
    -- Get the indices of the bracketed spans in the line
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false) -- Get the line text
    local bracketed_span_pattern = '%b[](%b{})'
    local indices, prev_last, continue = {}, 1, true

    while continue do
        -- Get the indices of any match on the current line
        local first, last = string.find(line[1], bracketed_span_pattern, prev_last)
        -- Check if there's a match that begins after the last from the previous
        -- iteration of the loop
        if first and last then
            -- If there is, check if the match overlaps with the cursor position
            if first - 1 <= col and last - 1 >= col then
                -- If it does overlap, save the indices of the match
                indices = { first = first, last = last }
                -- End the loop
                continue = false
            else
                -- If it doesn't overlap, save the end index of the match so
                -- we can look for a match following it on the next loop.
                prev_last = last
            end
        else
            continue = nil
        end
    end

    -- Check if a bracketed span was found under the cursor
    if continue == false then
        -- If one was found, get correct part of the match
        -- and return it
        local utils = require('mkdnflow').utils
        if part == 'text' then
            local text_pattern = '(%b[])%b{}'
            local span = string.sub(line[1], indices['first'], indices['last'])
            local text = string.sub(string.match(span, text_pattern), 2, -2)
            -- Return the text and the indices of the bracketed span
            return text, indices['first'], indices['last'], row
        elseif part == 'attr' then
            local attr_pattern = '%b[](%b{})'
            local attr = string.sub(
                string.match(string.sub(line[1], indices['first'], indices['last']), attr_pattern),
                2,
                -2
            )
            local attr_first, attr_last = line[1]:find('%]%{' .. vim.pesc(attr), indices['first'])
            attr_first = attr_first + 2
            return attr, attr_first, attr_last, row
        end
    else
        return nil
    end
end

-- =============================================================================
-- URL and path utilities
-- =============================================================================

--- Determine whether a string contains a URL
---@param string string The string to search for a URL
---@param to_return? 'boolean'|'positions' What to return (defaults to 'boolean')
---@param col? integer If provided, only match URLs overlapping this 0-indexed column
---@return boolean|integer|nil result Boolean if to_return is 'boolean'; start position if 'positions'
---@return integer|nil last End position (only when to_return is 'positions')
M.hasUrl = function(string, to_return, col)
    to_return = to_return or 'boolean'
    col = col or nil
    -- This function based largely on the solution in https://stackoverflow.com/questions/23590304/finding-a-url-in-a-string-lua-pattern
    -- Table of top-level domains
    local tlds = {
        ac = true,
        ad = true,
        ae = true,
        aero = true,
        af = true,
        ag = true,
        ai = true,
        al = true,
        am = true,
        an = true,
        ao = true,
        aq = true,
        ar = true,
        arpa = true,
        as = true,
        asia = true,
        at = true,
        au = true,
        aw = true,
        ax = true,
        az = true,
        ba = true,
        bb = true,
        bd = true,
        be = true,
        bf = true,
        bg = true,
        bh = true,
        bi = true,
        biz = true,
        bj = true,
        bm = true,
        bn = true,
        bo = true,
        br = true,
        bs = true,
        bt = true,
        bv = true,
        bw = true,
        by = true,
        bz = true,
        ca = true,
        cat = true,
        cc = true,
        cd = true,
        cf = true,
        cg = true,
        ch = true,
        ci = true,
        ck = true,
        cl = true,
        cm = true,
        cn = true,
        co = true,
        com = true,
        coop = true,
        cr = true,
        cs = true,
        cu = true,
        cv = true,
        cx = true,
        cy = true,
        cz = true,
        dd = true,
        de = true,
        dj = true,
        dk = true,
        dm = true,
        ['do'] = true,
        dz = true,
        ec = true,
        edu = true,
        ee = true,
        eg = true,
        eh = true,
        er = true,
        es = true,
        et = true,
        eu = true,
        fi = true,
        firm = true,
        fj = true,
        fk = true,
        fm = true,
        fo = true,
        fr = true,
        fx = true,
        ga = true,
        gb = true,
        gd = true,
        ge = true,
        gf = true,
        gh = true,
        gi = true,
        gl = true,
        gm = true,
        gn = true,
        gov = true,
        gp = true,
        gq = true,
        gr = true,
        gs = true,
        gt = true,
        gu = true,
        gw = true,
        gy = true,
        hk = true,
        hm = true,
        hn = true,
        hr = true,
        ht = true,
        hu = true,
        id = true,
        ie = true,
        il = true,
        im = true,
        ['in'] = true,
        info = true,
        int = true,
        io = true,
        iq = true,
        ir = true,
        is = true,
        it = true,
        je = true,
        jm = true,
        jo = true,
        jobs = true,
        jp = true,
        ke = true,
        kg = true,
        kh = true,
        ki = true,
        km = true,
        kn = true,
        kp = true,
        kr = true,
        kw = true,
        ky = true,
        kz = true,
        la = true,
        lb = true,
        lc = true,
        li = true,
        lk = true,
        lr = true,
        ls = true,
        lt = true,
        lu = true,
        lv = true,
        ly = true,
        ma = true,
        mc = true,
        md = false,
        me = true,
        mg = true,
        mh = true,
        mil = true,
        mk = true,
        ml = true,
        mm = true,
        mn = true,
        mo = true,
        mobi = true,
        mp = true,
        mq = true,
        mr = true,
        ms = true,
        mt = true,
        mu = true,
        museum = true,
        mv = true,
        mw = true,
        mx = true,
        my = true,
        mz = true,
        na = true,
        name = true,
        nato = true,
        nc = true,
        ne = true,
        net = true,
        nf = true,
        ng = true,
        ni = true,
        nl = true,
        no = true,
        nom = true,
        np = true,
        nr = true,
        nt = true,
        nu = true,
        nz = true,
        om = true,
        org = true,
        pa = true,
        pe = true,
        pf = true,
        pg = true,
        ph = true,
        pk = true,
        pl = true,
        pm = true,
        pn = true,
        post = true,
        pr = true,
        pro = true,
        ps = true,
        pt = true,
        pw = true,
        py = true,
        qa = true,
        re = true,
        ro = true,
        ru = true,
        rw = true,
        sa = true,
        sb = true,
        sc = true,
        sd = true,
        se = true,
        sg = true,
        sh = true,
        si = true,
        sj = true,
        sk = true,
        sl = true,
        sm = true,
        sn = true,
        so = true,
        sr = true,
        ss = true,
        st = true,
        store = true,
        su = true,
        sv = true,
        sy = true,
        sz = true,
        tc = true,
        td = true,
        tel = true,
        tf = true,
        tg = true,
        th = true,
        tj = true,
        tk = true,
        tl = true,
        tm = true,
        tn = true,
        to = true,
        tp = true,
        tr = true,
        travel = true,
        tt = true,
        tv = true,
        tw = true,
        tz = true,
        ua = true,
        ug = true,
        uk = true,
        um = true,
        us = true,
        uy = true,
        va = true,
        vc = true,
        ve = true,
        vg = true,
        vi = true,
        vn = true,
        vu = true,
        web = true,
        wf = true,
        ws = true,
        xxx = true,
        ye = true,
        yt = true,
        yu = true,
        za = true,
        zm = true,
        zr = true,
        zw = true,
    }
    -- Table of protocols
    local protocols = {
        [''] = 0,
        ['http://'] = 0,
        ['https://'] = 0,
        ['ftp://'] = 0,
    }
    -- Table for status of url search
    local finished = {}
    -- URL identified
    local found_url = nil
    -- Function to return the max value of the four inputs
    local max_of_four = function(a, b, c, d)
        return math.max(a + 0, b + 0, c + 0, d + 0)
    end
    -- For each group in the match, do some stuff
    local first, last
    for pos_start, url, prot, subd, tld, colon, port, slash, path, pos_end in
        string.gmatch(
            string,
            '()(([%w_.~!*:@&+$/?%%#-]-)(%w[-.%w]*%.)(%w+)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))()'
        )
    do
        if
            protocols[prot:lower()] == (1 - #slash) * #path
            and not subd:find('%W%W')
            and (colon == '' or port ~= '' and port + 0 < 65536)
            and (
                tlds[tld:lower()]
                or tld:find('^%d+$')
                    and subd:find('^%d+%.%d+%.%d+%.$')
                    and max_of_four(tld, subd:match('^(%d+)%.(%d+)%.(%d+)%.$')) < 256
            )
        then
            finished[pos_start] = true
            found_url = true
            if col then
                if col >= pos_start - 1 and col < pos_end - 1 then
                    first, last = pos_start, pos_end
                end
            end
        end
    end
    for pos_start, url, prot, dom, colon, port, slash, path, pos_end in
        string.gmatch(
            string,
            '()((%f[%w]%a+://)(%w[-.%w]*)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))()'
        )
    do
        if
            not finished[pos_start]
            and not (dom .. '.'):find('%W%W')
            and protocols[prot:lower()] == (1 - #slash) * #path
            and (colon == '' or port ~= '' and port + 0 < 65536)
        then
            found_url = true
            if col then
                if col >= pos_start - 1 and col < pos_end - 1 then
                    first, last = pos_start, pos_end
                end
            end
        end
    end
    if found_url ~= true then
        found_url = false
    end
    if to_return == 'boolean' then
        return found_url
    elseif to_return == 'positions' then
        if found_url then
            return first, last
        end
    end
end

--- Apply the user's `transform_on_create` function to text when creating a link
---@param text string The text to transform
---@return string text The transformed text (or unchanged if no transform is configured)
M.transformPath = function(text)
    local config = require('mkdnflow').config
    local links = config.links
    if type(links.transform_on_create) ~= 'function' or not links.transform_on_create then
        return text
    else
        return (links.transform_on_create(text))
    end
end

--- Convert a heading to an anchor using the legacy ASCII-only behavior (for backwards compatibility)
---@param heading_text string The heading text (with or without leading `#` characters)
---@return string anchor The anchor string (e.g., "#my-heading")
M.formatAnchorLegacy = function(heading_text)
    local path_text = heading_text
    -- Step 1: Strip non-ASCII chars (original behavior - this leaves spaces from stripped chars)
    path_text = string.gsub(path_text, '[^%a%s%d%-_]', '')
    -- Step 2: Remove leading single space (NOT the space after stripped # chars)
    path_text = string.gsub(path_text, '^ ', '')
    -- Step 3: Replace spaces with hyphens
    path_text = string.gsub(path_text, ' ', '-')
    -- Step 4: Collapse double hyphens to single
    path_text = string.gsub(path_text, '%-%-', '-')
    -- Step 5: Add # prefix and lowercase
    path_text = '#' .. string.lower(path_text)
    return path_text
end

--- Strip bracket syntax from citation text while preserving the `@` prefix
---@param text? string The citation text (e.g., "[@smith2020]")
---@return string|nil text The cleaned text (e.g., "@smith2020"), or nil if input was nil
M.cleanCitationText = function(text)
    if not text then
        return text
    end
    text = text:gsub('^%[', '')
    text = text:gsub('%]$', '')
    return text
end

--- Create a formatted markdown or wiki link from text
---@param text string The display text (or heading text for anchors)
---@param source? string An explicit source path; if nil, derived from text
---@param part? integer If 1, return only the text; if 2, return only the path
---@return string[]|string|nil result The formatted link as a single-element array, or a part if requested
M.formatLink = function(text, source, part)
    local config = require('mkdnflow').config
    local links = config.links
    local replacement, path_text
    -- If the text starts with a hash, format the link as an anchor link
    if string.sub(text, 0, 1) == '#' and not source then
        -- Remove leading hashes and spaces from display text
        text = string.gsub(text, '^#* *', '')
        -- Start with the cleaned text
        path_text = text
        -- Remove ASCII punctuation (blacklist approach, preserves Unicode letters)
        path_text = string.gsub(path_text, '[!"#$%%&\'%(%)%*%+,%./:;<=>%?@%[%]\\^`{|}~]', '')
        -- Replace each space with a hyphen (matches GitHub behavior - no collapsing)
        path_text = string.gsub(path_text, ' ', '-')
        -- Lowercase using vim.fn.tolower for Unicode support
        path_text = '#' .. vim.fn.tolower(path_text)
    elseif not source then
        path_text = M.transformPath(text)
        -- If no path_text, end here
        if not path_text then
            return
        end
        if not links.implicit_extension then
            path_text = path_text .. '.md'
        end
    else
        path_text = source
    end
    -- Format the replacement depending on the user's link style preference
    if links.style == 'wiki' then
        replacement = (links.compact and { '[[' .. text .. ']]' })
            or { '[[' .. path_text .. '|' .. text .. ']]' }
    else
        replacement = { '[' .. text .. ']' .. '(' .. path_text .. ')' }
    end
    -- Return the requested part
    if part == nil then
        return replacement
    elseif part == 1 then
        return text
    elseif part == 2 then
        return path_text
    end
end

-- =============================================================================
-- Link manipulation functions
-- =============================================================================

--- Create a link from the word under the cursor or from a visual selection
---@param args? {from_clipboard?: boolean, from_citation?: boolean, citation_bounds?: table, range?: boolean}
M.createLink = function(args)
    local config = require('mkdnflow').config
    local links = config.links
    local utils = require('mkdnflow').utils

    args = args or {}
    local from_clipboard = args.from_clipboard or false
    local from_citation = args.from_citation or false
    local citation_bounds = args.citation_bounds
    local range = args.range or false
    -- Get mode from vim
    local mode = vim.api.nvim_get_mode()['mode']
    -- Get the cursor position
    local position = vim.api.nvim_win_get_cursor(0)
    local row = position[1]
    local col = position[2]
    -- If the current mode is 'normal', make link from word under cursor
    if mode == 'n' and not range then
        -- Check if cursor is already on a link (including image links)
        local existing_link = M.getLinkUnderCursor()
        if existing_link then
            return -- Don't create a new link if one already exists
        end
        -- Get the text of the line the cursor is on
        local line = vim.api.nvim_get_current_line()
        local url_start, url_end = M.hasUrl(line, 'positions', col)
        if url_start and url_end then
            -- Prepare the replacement
            local url = line:sub(url_start, url_end - 1)
            local replacement = (links.style == 'wiki' and { '[[' .. url .. '|]]' })
                or { '[]' .. '(' .. url .. ')' }
            -- Replace
            vim.api.nvim_buf_set_text(0, row - 1, url_start - 1, row - 1, url_end - 1, replacement)
            -- Move the cursor to the name part of the link and change mode
            if links.style == 'wiki' then
                vim.api.nvim_win_set_cursor(0, { row, url_end + 2 })
            else
                vim.api.nvim_win_set_cursor(0, { row, url_start })
            end
            vim.cmd('startinsert')
        else
            -- Get the text under the cursor (WORD = contiguous non-whitespace)
            local cursor_word = vim.fn.expand('<cWORD>')
            -- Strip common sentence punctuation from edges, preserving
            -- path-meaningful characters (/, -, _, ~, #, @)
            -- Leading: strip , ; : ! ? ' " ( ) { } [ ] (NOT . — preserves dotfiles)
            cursor_word = cursor_word:gsub('^[,;:!?\'"(){}%[%]]+', '')
            -- Trailing: strip . , ; : ! ? ' " ( ) { } [ ]
            cursor_word = cursor_word:gsub('[.,;:!?\'"(){}%[%]]+$', '')
            -- Make a markdown link out of the date and cursor
            local replacement
            if from_clipboard then
                replacement = M.formatLink(cursor_word, vim.fn.getreg('+'))
            else
                replacement = M.formatLink(cursor_word)
            end
            -- If there's no replacement, stop here
            if not replacement then
                return
            end
            -- Find the (first) position of the matched word in the line
            local left, right = string.find(line, cursor_word, nil, true)
            -- Make sure it's not a duplicate of the word under the cursor, and if it
            -- is, perform the search until a match is found whose right edge follows
            -- the cursor position
            if cursor_word ~= '' then
                for _left, _right in utils.gmatch(line, vim.pesc(cursor_word)) do
                    if _right >= col then
                        left = _left
                        right = _right
                        break
                    end
                end
            else
                left, right = col + 1, col
            end
            -- Replace the word under the cursor w/ the formatted link replacement
            vim.api.nvim_buf_set_text(0, row - 1, left - 1, row - 1, right, replacement)
            vim.api.nvim_win_set_cursor(0, { row, col + 1 })
        end
    -- If current mode is 'visual', make link from selection
    elseif mode == 'v' or range then
        -- Get the start of the visual selection (the end is the cursor position)
        local vis = vim.fn.getpos('v')
        -- If the start of the visual selection is after the cursor position,
        -- use the cursor position as start and the visual position as finish
        local inverted = range and false or vis[3] > col
        local start, finish
        local start_row, start_col, end_row, end_col
        if range then
            start = vim.api.nvim_buf_get_mark(0, '<')
            finish = vim.api.nvim_buf_get_mark(0, '>')
            -- Convert to 0-indexed rows
            start_row = start[1] - 1
            start_col = start[2]
            end_row = finish[1] - 1
            end_col = finish[2] + 1
            -- Update start/finish for later use
            start[1] = start_row
            finish[1] = end_row
            -- If citation bounds are provided, expand the replacement area to
            -- cover the full citation, even if the visual selection was partial.
            -- Citation bounds use 1-indexed row/col; convert to 0-indexed.
            if citation_bounds then
                start_row = citation_bounds.start_row - 1
                start_col = citation_bounds.start_col - 1
                end_row = citation_bounds.end_row - 1
                end_col = citation_bounds.end_col
                start[1] = start_row
                start[2] = start_col
                finish[1] = end_row
                finish[2] = end_col - 1
            end
        else
            start = (inverted and { row - 1, col }) or { vis[2] - 1, vis[3] - 1 + vis[4] }
            finish = (inverted and { vis[2] - 1, vis[3] - 1 + vis[4] }) or { row - 1, col }
            start_row = (inverted and row - 1) or vis[2] - 1
            start_col = (inverted and col) or vis[3] - 1
            end_row = (inverted and vis[2] - 1) or row - 1
            -- If inverted, use the col value from the visual selection; otherwise, use the col value
            -- from start.
            end_col = (inverted and vis[3]) or finish[2] + 1
        end
        -- Make sure the selection is on a single line; otherwise, do nothing & throw a warning
        if start_row == end_row then
            local lines = vim.api.nvim_buf_get_lines(0, start[1], finish[1] + 1, false)

            -- Check if last byte is part of a multibyte character & adjust end index if so
            local is_multibyte_char =
                utils.isMultibyteChar({ buffer = 0, row = finish[1], start_col = end_col })
            if is_multibyte_char then
                end_col = is_multibyte_char['finish']
            end

            -- Reduce the text only to the visual selection
            lines[1] = lines[1]:sub(start_col + 1, end_col)

            -- If start and end are on different rows, reduce the text on the last line to the visual
            -- selection as well
            if start[1] ~= finish[1] then
                lines[#lines] = lines[#lines]:sub(start_col + 1, end_col)
            end
            -- Save the text selection & format as a link
            local text = table.concat(lines)
            local replacement
            if from_citation then
                text = M.cleanCitationText(text)
                local cite_path = text:gsub('^@', '')
                cite_path = M.transformPath(cite_path)
                if not cite_path then
                    return
                end
                if not links.implicit_extension then
                    cite_path = cite_path .. '.md'
                end
                replacement = M.formatLink(text, cite_path)
            else
                replacement = from_clipboard and M.formatLink(text, vim.fn.getreg('+'))
                    or M.formatLink(text)
            end
            -- If no replacement, end here
            if not replacement then
                return
            end
            -- Replace the visual selection w/ the formatted link replacement
            vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, replacement)
            -- Leave visual mode
            vim.api.nvim_feedkeys(utils.keycode('<Esc>'), 'x', true)
            -- Retain original cursor position
            vim.api.nvim_win_set_cursor(0, { row, col + 1 })
        else
            vim.notify(
                '⬇️  Creating links from multi-line visual selection not supported',
                vim.log.levels.WARN
            )
        end
    end
end

--- Remove the link under the cursor, keeping only the display text
M.destroyLink = function()
    -- Get link name, indices, and row the cursor is currently on
    local link = M.getLinkUnderCursor()
    if link then
        local link_name = M.getLinkPart(link, 'name')
        -- Replace the link with just the name
        vim.api.nvim_buf_set_text(0, link[4] - 1, link[5] - 1, link[6] - 1, link[7], { link_name })
    else
        vim.notify("⬇️  Couldn't find a link under the cursor to destroy!", vim.log.levels.WARN)
    end
end

--- Find the first row where heading_lines appears as consecutive lines in the buffer.
---@param lines string[] Buffer lines
---@param heading_lines string[] One or more heading lines to match
---@return integer|nil row 1-indexed row of the first heading line, or nil
local function findHeadingRow(lines, heading_lines)
    local n = #heading_lines
    for i = 1, #lines - n + 1 do
        local match = true
        for j = 1, n do
            if lines[i + j - 1] ~= heading_lines[j] then
                match = false
                break
            end
        end
        if match then
            return i
        end
    end
    return nil
end

--- Create a footnote reference at the cursor and a definition at the end of the document
---@param args? {label?: string} If label is provided, use it; otherwise auto-increment
M.createFootnote = function(args)
    args = args or {}
    local config = require('mkdnflow').config

    -- Scan buffer for existing footnote definitions
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local max_numeric = 0
    local last_def_row = nil -- 1-indexed
    local existing_labels = {}
    local heading_lines = config.footnotes and config.footnotes.heading_lines
    local heading_row = heading_lines and findHeadingRow(lines, heading_lines)

    for i, line in ipairs(lines) do
        local label = string.match(line, '^%s?%s?%s?%[%^(.-)%]:%s')
        if label then
            existing_labels[label] = true
            last_def_row = i
            local num = tonumber(label)
            if num and num > max_numeric then
                max_numeric = num
            end
        end
    end

    -- Determine the label
    local label = args.label
    if label then
        if existing_labels[label] then
            vim.notify('Footnote [^' .. label .. '] already exists!', vim.log.levels.WARN)
            return
        end
    else
        label = tostring(max_numeric + 1)
    end

    -- Insert the reference after the current word and any trailing punctuation
    local position = vim.api.nvim_win_get_cursor(0)
    local row = position[1]
    local col = position[2]
    local ref_text = '[^' .. label .. ']'

    local line = vim.api.nvim_get_current_line()
    local punct_pat = '[%.,:;%?!%)%]"]'
    local i = col + 1 -- Lua 1-indexed

    -- Step 1: scan forward past word characters (non-whitespace, non-punctuation)
    while i <= #line do
        local ch = line:sub(i, i)
        if ch:match('%s') or ch:match(punct_pat) then
            break
        end
        i = i + 1
    end

    -- Step 2: scan forward past trailing punctuation
    while i <= #line and line:sub(i, i):match(punct_pat) do
        i = i + 1
    end

    local insert_col = i - 1 -- Back to 0-indexed
    vim.api.nvim_buf_set_text(0, row - 1, insert_col, row - 1, insert_col, { ref_text })

    -- Build and place the definition
    local def_line = '[^' .. label .. ']: '
    local target_row -- 1-indexed row of the new definition

    if last_def_row then
        -- Add after the last existing definition
        vim.api.nvim_buf_set_lines(0, last_def_row, last_def_row, false, { def_line })
        target_row = last_def_row + 1
    else
        -- No existing definitions: append to end of buffer
        local line_count = vim.api.nvim_buf_line_count(0)
        local last_line = vim.api.nvim_buf_get_lines(0, line_count - 1, line_count, false)[1]
        local append = {}

        -- Blank separator if buffer doesn't end with an empty line
        if last_line ~= '' then
            table.insert(append, '')
        end

        -- Heading (if configured and not already in buffer)
        if heading_lines and not heading_row then
            for _, hl in ipairs(heading_lines) do
                table.insert(append, hl)
            end
            table.insert(append, '')
        end

        table.insert(append, def_line)
        vim.api.nvim_buf_set_lines(0, line_count, line_count, false, append)
        target_row = line_count + #append
    end

    -- Set jumplist mark so '' returns to the reference position
    vim.cmd("normal! m'")
    -- Jump to the definition line
    vim.api.nvim_win_set_cursor(0, { target_row, 0 })
    -- Enter insert mode at end of line so user can type the definition
    vim.cmd('startinsert!')
end

--- Find the end row of a multi-line footnote definition
--- Continuation lines are indented by 4+ spaces or a tab. Blank lines followed
--- by indented continuation are part of the same definition.
---@param lines string[] Buffer lines
---@param start_row integer 1-indexed row where the definition starts
---@return integer end_row 1-indexed inclusive end row
local function find_def_end(lines, start_row)
    local i = start_row + 1
    while i <= #lines do
        local line = lines[i]
        if line == '' then
            -- Blank line: check if next non-blank line is an indented continuation
            local j = i + 1
            while j <= #lines and lines[j] == '' do
                j = j + 1
            end
            if j <= #lines and (lines[j]:match('^    ') or lines[j]:match('^\t')) then
                i = j + 1
            else
                return i - 1
            end
        elseif line:match('^    ') or line:match('^\t') then
            i = i + 1
        elseif line:match('^%s?%s?%s?%[%^(.-)%]:%s') then
            return i - 1
        else
            return i - 1
        end
    end
    return #lines
end

--- Core implementation for both MkdnRenumberFootnotes and MkdnRefreshFootnotes.
--- Scans the buffer for footnotes, optionally renumbers labels, and consolidates
--- definitions under the configured heading in order of first appearance.
---@param opts {renumber_all: boolean} renumber_all=true converts all labels to
---  sequential integers; renumber_all=false only renumbers numeric labels.
local function refreshFootnotes(opts)
    local renumber_all = opts.renumber_all
    local config = require('mkdnflow').config
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local def_pat = '^%s?%s?%s?%[%^(.-)%]:%s'
    local heading_lines = config.footnotes and config.footnotes.heading_lines

    -- Phase 1: Find definitions with multi-line support, detect duplicates
    local definitions = {} -- label -> { start_row, end_row }
    local def_labels_ordered = {} -- preserve discovery order for stable orphan handling
    local heading_row = heading_lines and findHeadingRow(lines, heading_lines)

    local i = 1
    while i <= #lines do
        local label = string.match(lines[i], def_pat)
        if label then
            if definitions[label] then
                vim.notify(
                    '⬇️  Duplicate footnote definition [^'
                        .. label
                        .. '] on lines '
                        .. definitions[label].start_row
                        .. ' and '
                        .. i
                        .. '. Aborting.',
                    vim.log.levels.WARN
                )
                return
            end
            local end_row = find_def_end(lines, i)
            definitions[label] = { start_row = i, end_row = end_row }
            table.insert(def_labels_ordered, label)
            i = end_row + 1
        else
            i = i + 1
        end
    end

    -- Phase 2: Build first-appearance order from references.
    -- On definition lines for label X, skip only the self-label [^X] but still
    -- scan for cross-references to other footnotes on the same line.
    local order = {} -- sequential list of labels
    local seen = {} -- label -> true
    for idx, line in ipairs(lines) do
        local def_label = string.match(line, def_pat)
        for label in string.gmatch(line, '%[%^(.-)%]') do
            local is_self_def = (def_label and label == def_label)
            if not is_self_def and not seen[label] then
                table.insert(order, label)
                seen[label] = true
            end
        end
    end

    -- Phase 3: Append orphan definitions (defined but never referenced)
    for _, label in ipairs(def_labels_ordered) do
        if not seen[label] then
            table.insert(order, label)
            seen[label] = true
        end
    end

    if #order == 0 then
        vim.notify('⬇️  No footnotes found in buffer.', vim.log.levels.INFO)
        return
    end

    -- Phase 4: Build label mapping
    local label_map = {} -- old_label -> new_label (only for labels that change)
    if renumber_all then
        for idx, old_label in ipairs(order) do
            label_map[old_label] = tostring(idx)
        end
    else
        local num_counter = 0
        for _, old_label in ipairs(order) do
            if tonumber(old_label) then
                num_counter = num_counter + 1
                label_map[old_label] = tostring(num_counter)
            end
        end
    end

    -- Phase 5: Replace labels in all lines via gsub
    local new_lines = {}
    for idx, line in ipairs(lines) do
        new_lines[idx] = string.gsub(line, '%[%^(.-)%]', function(label)
            local new_label = label_map[label]
            if new_label then
                return '[^' .. new_label .. ']'
            end
            return '[^' .. label .. ']'
        end)
    end

    -- Phase 6: Extract definition blocks (from new_lines, post-replacement)
    -- and collect them in appearance order
    local ordered_def_blocks = {} -- array of { lines[] }
    for _, old_label in ipairs(order) do
        local def = definitions[old_label]
        if def then
            local block = {}
            for r = def.start_row, def.end_row do
                table.insert(block, new_lines[r])
            end
            table.insert(ordered_def_blocks, block)
        end
    end

    -- Phase 7: Build body (all lines except definitions and heading)
    local is_excluded_row = {}
    for _, def in pairs(definitions) do
        for r = def.start_row, def.end_row do
            is_excluded_row[r] = true
        end
    end
    if heading_row and heading_lines then
        for j = 0, #heading_lines - 1 do
            is_excluded_row[heading_row + j] = true
        end
    end

    local body = {}
    for idx, line in ipairs(new_lines) do
        if not is_excluded_row[idx] then
            table.insert(body, line)
        end
    end

    -- Strip trailing blank lines
    while #body > 0 and body[#body] == '' do
        table.remove(body)
    end

    -- Collapse consecutive blank lines (left behind by removed definitions)
    local cleaned = {}
    for _, line in ipairs(body) do
        if not (line == '' and #cleaned > 0 and cleaned[#cleaned] == '') then
            table.insert(cleaned, line)
        end
    end
    body = cleaned

    -- Phase 8: Build footnotes section
    local footnotes_section = {}
    if #ordered_def_blocks > 0 then
        if heading_lines then
            for _, hl in ipairs(heading_lines) do
                table.insert(footnotes_section, hl)
            end
            table.insert(footnotes_section, '')
        end
        for _, block in ipairs(ordered_def_blocks) do
            for _, line in ipairs(block) do
                table.insert(footnotes_section, line)
            end
        end
    end

    -- Phase 9: Assemble result
    local result = {}
    for _, line in ipairs(body) do
        table.insert(result, line)
    end
    if #footnotes_section > 0 then
        table.insert(result, '')
        for _, line in ipairs(footnotes_section) do
            table.insert(result, line)
        end
    end

    -- Phase 10: No-op detection (compare result with original)
    if #result == #lines then
        local changed = false
        for idx = 1, #result do
            if result[idx] ~= lines[idx] then
                changed = true
                break
            end
        end
        if not changed then
            vim.notify('⬇️  Footnotes are already up to date.', vim.log.levels.INFO)
            return
        end
    end

    -- Phase 11: Atomic buffer update (single undo step)
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, result)
    if pos[1] > #result then
        pos[1] = #result
    end
    vim.api.nvim_win_set_cursor(0, pos)

    local relabeled = 0
    for old, new in pairs(label_map) do
        if old ~= new then
            relabeled = relabeled + 1
        end
    end
    if relabeled > 0 then
        vim.notify('⬇️  Refreshed footnotes (renumbered ' .. relabeled .. ').', vim.log.levels.INFO)
    else
        vim.notify('⬇️  Refreshed footnote definitions.', vim.log.levels.INFO)
    end
end

--- Renumber all footnotes sequentially by order of first appearance.
--- Both numeric and string-labeled footnotes are converted to sequential integers.
--- Definitions are consolidated under the configured heading.
M.renumberFootnotes = function()
    refreshFootnotes({ renumber_all = true })
end

--- Refresh footnote numbering and definition order.
--- Only numeric labels are renumbered; string labels are preserved.
--- Definitions are consolidated under the configured heading in appearance order.
M.refreshFootnotes = function()
    refreshFootnotes({ renumber_all = false })
end

--- Follow the link under the cursor, or create a new link if none exists
---@param args? {path?: string, anchor?: string, range?: boolean}
M.followLink = function(args)
    local config = require('mkdnflow').config
    local links = config.links

    -- Path can be provided as an argument (this is currently only used when
    -- this function retrieves a path from the citation handler). If no path
    -- is provided as an arg, get the path under the cursor via getLinkPart().
    args = args or {}
    local path = args.path
    local anchor = args.anchor
    local range = args.range or false
    local link_type, link
    if path or anchor then
        path, anchor = path, anchor
    else
        link = M.getLinkUnderCursor()
        path, anchor, link_type = M.getLinkPart(link, 'source')
    end
    -- Footnote handling: jump to definition or back to first reference
    if link_type == 'footnote_ref' or link_type == 'footnote_definition' then
        local source = link:get_source()
        if source and source.start_row and source.start_row > 0 then
            vim.api.nvim_win_set_cursor(0, { source.start_row, source.start_col - 1 })
        else
            local direction = link_type == 'footnote_ref' and 'definition' or 'reference'
            vim.notify("Couldn't find footnote " .. direction .. '!', vim.log.levels.WARN)
        end
        return
    end

    local is_citation = link_type == 'citation' or link_type == 'pandoc_citation'
    if is_citation and range then
        -- Pass citation bounds so createLink can expand partial selections
        -- to the full citation. Link bounds are 1-indexed row, 1-indexed col.
        local citation_bounds = link
                and {
                    start_row = link[4],
                    start_col = link[5],
                    end_row = link[6],
                    end_col = link[7],
                }
            or nil
        M.createLink({ range = range, from_citation = true, citation_bounds = citation_bounds })
        return
    end
    if (path and path ~= '') or (anchor and anchor ~= '') then
        require('mkdnflow').paths.handlePath(path, anchor, link_type)
    elseif link_type == 'ref_style_link' then -- If this condition is met, no reference was found
        vim.notify("⬇️  Couldn't find a matching reference label!", vim.log.levels.WARN)
    elseif links.auto_create then
        M.createLink({ range = range })
    end
end

--- Create a Pandoc bracketed span from a visual selection with an auto-generated ID attribute
M.tagSpan = function()
    -- Get mode & cursor position from vim
    local mode, position = vim.api.nvim_get_mode()['mode'], vim.api.nvim_win_get_cursor(0)
    local row, col = position[1], position[2]
    -- If the current mode is 'normal', make link from word under cursor
    if mode == 'v' then
        -- Get the start of the visual selection (the end is the cursor position)
        local vis = vim.fn.getpos('v')
        -- If the start of the visual selection is after the cursor position,
        -- use the cursor position as start and the visual position as finish
        local inverted = vis[3] > col
        local start = (inverted and { row - 1, col }) or { vis[2] - 1, vis[3] - 1 + vis[4] }
        local finish = (inverted and { vis[2] - 1, vis[3] - 1 + vis[4] }) or { row - 1, col }
        local start_row = (inverted and row - 1) or vis[2] - 1
        local start_col = (inverted and col) or vis[3] - 1
        local end_row = (inverted and vis[2] - 1) or row - 1
        local end_col = (inverted and vis[3]) or col + 1
        local region =
            vim.region(0, start, finish, vim.fn.visualmode(), (vim.o.selection ~= 'exclusive'))
        local lines = vim.api.nvim_buf_get_lines(0, start[1], finish[1] + 1, false)
        lines[1] = lines[1]:sub(region[start[1]][1] + 1, region[start[1]][2])
        if start[1] ~= finish[1] then
            lines[#lines] = lines[#lines]:sub(region[finish[1]][1] + 1, region[finish[1]][2])
        end
        -- Save the text selection & replace spaces with dashes
        local text = table.concat(lines)
        local replacement = '[' .. text .. ']' .. '{' .. M.formatLink('#' .. text, nil, 2) .. '}'
        -- Replace the visual selection w/ the formatted link replacement
        vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, { replacement })
        -- Leave visual mode
        vim.api.nvim_feedkeys(utils.keycode('<Esc>'), 'x', true)
        -- Retain original cursor position
        vim.api.nvim_win_set_cursor(0, { row, col + 1 })
    end
end

return M
