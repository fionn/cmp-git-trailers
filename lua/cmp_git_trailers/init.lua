---@diagnostic disable-next-line: name-style-check
local source = {}

---@type vim.SystemObj[]
local jobs = {}
local updated_trailers = false
local updated_authors = false

---@type lsp.CompletionItem[]
local trailer_table = {
    {
        label = "Counterpart-to:",
        documentation = "Commit or PR that this relates to, typically in another repository."
    },
    {
        label = "Follow-up-to:",
        documentation = "Commit or PR that this succeeds."
    },
    {
        label = "Fixup-for:",
        documentation = "Commit that would have been subject to a fixup if not already pushed."
    },
    {
        label = "Signed-off-by:",
        -- Documentation adapted from git help commit.
        documentation = "The meaning of a signoff depends on the project to which you’re committing. For example, it may certify that the committer has the rights to submit the work under the project’s license or agrees to some contributor representation, such as a Developer Certificate of Origin. See https://developercertificate.org."
    },
    {
        label = "Co-authored-by:",
        documentation = "Attribute the commit to multiple authors.\n\nSee https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors#creating-a-commit-with-multiple-authors."
    },
    {
        label = "On-behalf-of: @",
        documentation = "Attribute the commit to an organisation.\n\nSee https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors#creating-a-commit-on-behalf-of-an-organization."
    },
    {
        label = "Assisted-by:",
        documentation = "Provide attribution for tool use.\n\nSee https://docs.kernel.org/process/coding-assistants.html#attribution."
    },
    {
        label = "See:",
        documentation = "URL to some related resource for additional context."
    },
    {
        label = "Ticket:",
        documentation = "Unique identifier in the relevant tracking system."
    },
    {
        label = "Closes: #",
        documentation = "Link to an issue this commit closes.\n\nSee https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword."
    },
    {
        label = "Fixes: #",
        documentation = "Link to an issue this commit fixes.\n\nSee https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword."
    },
    {
        label = "skip-checks: true",
        documentation = "Skip CI/CD workflows in GitHub Actions.\n\nSee https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs."
    }
}

---@type lsp.CompletionItem[]
local author_table = {}

-- Get all trailers in the past 100 commits and merge them with our hard-coded
-- list (by mutating it as a side effect).
local function update_symbol_table()
    if #jobs > 0 then return end
    if updated_trailers then return end

    ---@type vim.SystemOpts
    local system_opts = {
        text = true,
        timeout = 1000
    }
    local cmd = {"git", "log", "--pretty=format:%(trailers:keyonly=true)", "-100"}
    local job = vim.system(cmd, system_opts, function(out)
        if out.code ~= 0 then
            updated_trailers = true
            vim.schedule(function()
                vim.notify("Failed to get trailers from log", vim.log.levels.DEBUG)
            end)
            return
        end

        ---@type string[]
        local labels = {}
        for _, s in ipairs(trailer_table) do
            table.insert(labels, s.label)
        end

        ---@type lsp.CompletionItem[]
        local trailers = {}
        for key in out.stdout:gmatch("[^\n]+") do
            key = key .. ":"
            if not vim.list_contains(labels, key) then
                table.insert(trailers, {label = key})
            end
        end

        vim.list.unique(trailers)
        vim.list_extend(trailer_table, trailers)
        updated_trailers = true
    end)

    table.insert(jobs, job)
end

-- Get authors from the commit log and Co-authored-by trailers as candidate
-- co-authors for completion. We do this synchronously and mutate the global
-- table, since we don't have any results to fall back on and we only want to
-- do it at most once.
local function update_author_table()
    if updated_authors then return end
    updated_authors = true

    local cmd_from_authors = {"git", "log", "--pretty=%an <%ae>", "-100"}
    local log_authors_job = vim.system(cmd_from_authors, {text = true})

    local cmd_from_trailers = {"git", "log", "--pretty=format:%(trailers:key=Co-authored-by,valueonly)", "-100"}
    local trailer_authors_job = vim.system(cmd_from_trailers, {text = true})

    local log_authors = log_authors_job:wait(1000)
    if log_authors.code ~= 0 then
        vim.notify("Failed to get authors from log", vim.log.levels.DEBUG)
        return
    end

    ---@type string[]
    local seen = {}

    for author in log_authors.stdout:gmatch("[^\n]+") do
        if not vim.list_contains(seen, author) then
            table.insert(seen, author)
            table.insert(author_table, {label = author})
        end
    end

    local trailer_authors = trailer_authors_job:wait(1000)
    if trailer_authors.code ~= 0 then
        vim.notify("Failed to get authors from trailers", vim.log.levels.DEBUG)
        return
    end

    for author in trailer_authors.stdout:gmatch("[^\n]+") do
        if not vim.list_contains(seen, author) then
            table.insert(seen, author)
            table.insert(author_table, {label = author})
        end
    end
end

function source:is_available()
    return vim.bo.filetype == "gitcommit"
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
    -- Asynchronously update the symbol table with trailers from the commit log,
    -- if any. This may or may not complete before the callback, but if we lose
    -- the race we can still offer the default completions and then offer
    -- additional ones if re-invoked. Ideally we could call this in some
    -- source:init method so it's pre-populated, but this doesn't exist. Second
    -- best would be to register an autocommand, but that seems inappropriate
    -- for a completion source.
    update_symbol_table()

    if params.context.cursor.row < 3 then
        -- The cursor is on the subject or gap between subject and body, where
        -- trailers are not allowed, so don't offer any completion candidates.
        callback()
        return
    end

    if params.context.cursor_before_line:match("^Co%-authored%-by: .*") then
        update_author_table()
        callback(author_table)
        return
    end

    if not params.context.cursor_before_line:match("^%S*$") then
        -- The cursor is not on a (possibly empty) word at the start of a line,
        -- so this can't be a trailer, so don't offer any completion candidates.
        callback()
        return
    end

    callback({items = trailer_table, isIncomplete = not updated_trailers})
end

return source
