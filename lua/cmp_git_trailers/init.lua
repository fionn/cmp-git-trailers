---@diagnostic disable-next-line: name-style-check
local source = {}

---@type vim.SystemOpts
local system_opts = {
    text = true,
    timeout = 1000
}

local updated_trailers = false
local updated_identity_from_self = false
local updated_identities_from_trailers = false

---@type lsp.CompletionItem[]
local global_trailers = {
    {
        label = "Counterpart-to",
        insertText = "Counterpart-to: ",
        documentation = "Commit or PR that this relates to, typically in another repository."
    },
    {
        label = "Follow-up-to",
        insertText = "Follow-up-to: ",
        documentation = "Commit or PR that this succeeds."
    },
    {
        label = "Fixup-for",
        insertText = "Fixup-for: ",
        documentation = "Commit that would have been subject to a fixup if not already pushed."
    },
    {
        label = "Signed-off-by",
        insertText = "Signed-off-by: ",
        -- Documentation adapted from git help commit.
        documentation = "The meaning of a signoff depends on the project to which you’re committing. For example, it may certify that the committer has the rights to submit the work under the project’s license or agrees to some contributor representation, such as a Developer Certificate of Origin. See https://developercertificate.org."
    },
    {
        label = "Co-authored-by",
        insertText = "Co-authored-by: ",
        documentation = "Attribute the commit to multiple authors.\n\nSee https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors#creating-a-commit-with-multiple-authors."
    },
    {
        label = "Acked-by",
        insertText = "Acked-by: ",
        documentation = "This trailer says that the person who is more familiar with the area the patch attempts to modify liked the patch."
    },
    {
        label = "Reviewed-by",
        insertText = "Reviewed-by: ",
        documentation = "Offered by the reviewers themselves when they are completely satisfied with the patch after a detailed analysis.\n\nSee https://reviewerstatement.org/"
    },
    {
        label = "Helped-by",
        insertText = "Helped-by: ",
        documentation = "Used to credit someone who suggested ideas for changes without providing the precise changes in patch form."
    },
    {
        label = "Reported-by",
        insertText = "Reported-by: ",
        documentation = "Used to credit someone who found the bug that the patch attempts to fix."
    },
    {
        label = "On-behalf-of",
        insertText = "On-behalf-of: @",
        documentation = "Attribute the commit to an organisation.\n\nSee https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors#creating-a-commit-on-behalf-of-an-organization."
    },
    {
        label = "Assisted-by",
        insertText = "Assisted-by: ",
        documentation = "Provide attribution for tool use.\n\nSee https://docs.kernel.org/process/coding-assistants.html#attribution."
    },
    {
        label = "See",
        insertText = "See: ",
        documentation = "URL to some related resource for additional context."
    },
    {
        label = "Ticket",
        insertText = "Ticket: ",
        documentation = "Unique identifier in the relevant tracking system."
    },
    {
        label = "Closes",
        insertText = "Closes: #",
        documentation = "Link to an issue this commit closes.\n\nSee https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword."
    },
    {
        label = "Fixes",
        insertText = "Fixes: #",
        documentation = "Link to an issue this commit fixes.\n\nSee https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword."
    },
    {
        label = "skip-checks",
        insertText = "skip-checks: true",
        documentation = "Skip CI/CD workflows in GitHub Actions.\n\nSee https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs."
    }
}

---@type lsp.CompletionItem[]
local global_identities = {}

-- Get all trailers in the past 100 commits and merge them with our hard-coded
-- list (by mutating it as a side effect).
local function update_global_trailers()
    if updated_trailers then return end
    updated_trailers = true

    local cmd = {"git", "log", "--format=%(trailers:keyonly)", "-100"}
    vim.system(cmd, system_opts, function(out)
        if out.code ~= 0 then
            vim.schedule(function()
                vim.notify("Failed to get trailers from log", vim.log.levels.DEBUG)
            end)
            return
        end

        ---@type string[]
        local labels = {}
        for _, s in ipairs(global_trailers) do
            table.insert(labels, s.label)
        end

        ---@type lsp.CompletionItem[]
        local trailers = {}
        for key in assert(out.stdout):gmatch("[^\n]+") do
            if not vim.list_contains(labels, key) then
                table.insert(trailers, {
                    label = key,
                    insertText = key .. ": ",
                    detail = "Previously seen trailer"
                })
            end
        end

        vim.list.unique(trailers, function(x) return x.label end)
        vim.list_extend(global_trailers, trailers)
    end)
end

-- Get authors from the commit log and identities from trailers as candidates
-- for completion. We do this synchronously and mutate the global table, since
-- we don't have any results to fall back on.
---@param query string
local function update_global_identities(query)
    ---@type vim.SystemObj[]
    local subprocesses = {}
    local mutated = false

    -- Add user's identity, useful for signoff. We do this conditionally since
    -- we only want to do it once.
    if not updated_identity_from_self then
        updated_identity_from_self = true
        table.insert(subprocesses, vim.system({"git", "var", "GIT_AUTHOR_IDENT"}, system_opts, function(out)
            if out.code ~= 0 then
                vim.schedule(function()
                    vim.notify("Failed to get identity from Git configuration", vim.log.levels.WARN)
                end)
                return
            end

            local name, email = assert(out.stdout):match("^(.-) <([^>]+)>")
            ---@type string
            local identity = assert(name) .. " <" .. assert(email) .. ">"
            table.insert(global_identities, {
                label = identity,
                documentation = identity,
                detail = "Self",
                kind = 5
            })
            mutated = true
        end))
    end

    -- Scour Co-authored-by and Signed-off-by trailers for identities. We do
    -- this conditionally since we only want to do it once.
    if not updated_identities_from_trailers then
        updated_identities_from_trailers = true
        local cmd_trailer_identities = {"git", "log",
            "--format=%(trailers:key=Co-authored-by,key=Signed-off-by,valueonly)",
            "-100"}
        table.insert(subprocesses, vim.system(cmd_trailer_identities, system_opts, function(out)
            if out.code ~= 0 then
                vim.schedule(function()
                    vim.notify("Failed to get authors from trailers", vim.log.levels.DEBUG)
                end)
                return
            end

            for identity in assert(out.stdout):gmatch("[^\n]+") do
                table.insert(global_identities, {
                    label = identity,
                    documentation = identity,
                    detail = "From trailers",
                    kind = 5
                })
                mutated = true
            end
        end))
    end

    -- Add identities from previous commit authors, dynamic based on the prefix.
    local cmd_from_authors = {"git", "log", "--author=" .. query, "--format=%an <%ae>", "-100"}
    table.insert(subprocesses, vim.system(cmd_from_authors, system_opts, function(out)
        if out.code ~= 0 then
            vim.schedule(function()
                vim.notify("Failed to get authors from log", vim.log.levels.DEBUG)
            end)
            return
        end

        for author in assert(out.stdout):gmatch("[^\n]+") do
            table.insert(global_identities, {
                label = author,
                documentation = author,
                detail = "From previous authors",
                kind = 5
            })
            mutated = true
        end
    end))

    for _, proc in ipairs(subprocesses) do
        proc:wait(system_opts.timeout)
    end

    if mutated then
        vim.list.unique(global_identities, function(x) return x.label end)
    end
end

---@diagnostic disable-next-line
function source:is_available()
    return vim.bo.filetype == "gitcommit"
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
---@diagnostic disable-next-line
function source:complete(params, callback)
    -- Asynchronously update the symbol table with trailers from the commit log,
    -- if any. This may or may not complete before the callback, but if we lose
    -- the race we can still offer the default completions and then offer
    -- additional ones if re-invoked. Ideally we could call this in some
    -- source:init method so it's pre-populated, but this doesn't exist. Second
    -- best would be to register an autocommand, but that seems inappropriate
    -- for a completion source.
    update_global_trailers()

    if params.context.cursor.row < 3 then
        -- The cursor is on the subject or gap between subject and body, where
        -- trailers are not allowed, so don't offer any completion candidates.
        callback()
        return
    end

    local identity_prefix = params.context.cursor_before_line:match("^Co%-authored%-by: (.*)$")
        or params.context.cursor_before_line:match("^Signed%-off%-by: (.*)$")
        or params.context.cursor_before_line:match("^Acked%-by: (.*)$")
        or params.context.cursor_before_line:match("^Reviewed%-by: (.*)$")
        or params.context.cursor_before_line:match("^Helped%-by: (.*)$")
        or params.context.cursor_before_line:match("^Reported%-by: (.*)$")
    if identity_prefix then
        update_global_identities(identity_prefix)
        callback({items = global_identities, isIncomplete = true})
        return
    end

    if not params.context.cursor_before_line:match("^%w+%S*$") then
        -- The cursor is not on a word at the start of a line, so this can't be
        -- a trailer, so don't offer any completion candidates.
        callback()
        return
    end

    callback({items = global_trailers, isIncomplete = not updated_trailers})
end

return source
