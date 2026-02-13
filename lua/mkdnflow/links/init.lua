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
            -- Get the word under the cursor
            local cursor_word = vim.fn.expand('<cword>')
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
                for _left, _right in utils.gmatch(line, cursor_word) do
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
