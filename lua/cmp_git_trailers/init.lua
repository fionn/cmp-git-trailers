---@diagnostic disable-next-line: name-style-check
local source = {}

---@type lsp.CompletionItem[]
local symbol_table = {
    {label = "Counterpart-to:"},
    {label = "Follow-up-to:"},
    {label = "Fixup-for:"},
    {label = "Signed-off-by:"},
    {label = "Co-authored-by:"},
    {label = "On-behalf-of:"},
    {label = "Assisted-by:"},
    {label = "See:"},
    {label = "Ticket:"},
    {label = "Closes:"},
    {label = "Fixes:"},
    {label = "skip-checks: true"}
}

function source:is_available()
    return vim.bo.filetype == "gitcommit"
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
    if params.context.cursor.row < 3 then
        -- The cursor is on the subject or gap between subject and body, where
        -- trailers are not allowed, so don't offer any completion candidates.
        callback()
        return
    end

    if not params.context.cursor_before_line:match("^%S*$") then
        -- The cursor is not on a (possibly empty) word at the start of a line,
        -- so this can't be a trailer, so don't offer any completion candidates.
        callback()
        return
    end

    callback(symbol_table)
end

return source
