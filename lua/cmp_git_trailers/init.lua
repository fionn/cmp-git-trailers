---@diagnostic disable-next-line: name-style-check
local source = {}

local updated_trailers = false
local updated_identities = false

---@type lsp.CompletionItem[]
local global_trailers = {
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
local global_identities = {}

-- Get all trailers in the past 100 commits and merge them with our hard-coded
-- list (by mutating it as a side effect).
local function update_trailers_table()
    if updated_trailers then return end
    updated_trailers = true

    ---@type vim.SystemOpts
    local system_opts = {
        text = true,
        timeout = 1000
    }
    local cmd = {"git", "log", "--pretty=format:%(trailers:keyonly=true)", "-100"}
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
            key = key .. ":"
            if not vim.list_contains(labels, key) then
                table.insert(trailers, {label = key})
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
local function update_identities_table(query)
    if query:match("^-") ~= nil then
        -- The query doesn't look like an author, so bail.
        return
    end

    ---@type vim.SystemOpts
    local system_opts = {
        text = true,
        timeout = 1000
    }

    local cmd_from_authors = {"git", "log", "--author=" .. query, "--pretty=%an <%ae>", "-100"}
    local commit_authors_proc = vim.system(cmd_from_authors, system_opts)

    local commit_authors = commit_authors_proc:wait(1000)
    if commit_authors.code ~= 0 then
        vim.notify("Failed to get authors from log", vim.log.levels.DEBUG)
        return
    end

    ---@type string[]
    local seen = {}

    for author in assert(commit_authors.stdout):gmatch("[^\n]+") do
        if not vim.list_contains(seen, author) then
            table.insert(seen, author)
            table.insert(global_identities, {label = author})
        end
    end

    -- Paranoia tells me to ensure the list is deduplicated.
    vim.list.unique(global_identities, function(x) return x.label end)

    -- The remainder deals with getting authors from trailers, which
    -- we don't query dynamically, so should only be run once.
    if updated_identities then return end
    updated_identities = true

    -- Set this job off first as it's probably going to take longer than the
    -- later ones.
    local cmd_trailer_identities = {"git", "log", "--pretty=format:%(trailers:key=Co-authored-by,key=Signed-off-by,valueonly)", "-100"}
    local trailer_identities_proc = vim.system(cmd_trailer_identities, system_opts)

    local name_proc = vim.system({"git", "config", "get", "user.name"}, system_opts)
    local email_proc = vim.system({"git", "config", "get", "user.email"}, system_opts)

    local self_name = name_proc:wait(1000)
    local self_email = email_proc:wait(1000)

    if self_name.code ~= 0 or self_email.code ~= 0 then
        vim.notify("Failed to get identity from Git configuration", vim.log.levels.WARN)
        return
    end

    local self = vim.trim(assert(self_name.stdout)) .. " <" .. vim.trim(assert(self_email.stdout)) .. ">"
    if not vim.list_contains(seen, self) then
        table.insert(seen, self)
        table.insert(global_identities, {
            label = self,
            documentation = "Self"
        })
    end

    local trailer_identities = trailer_identities_proc:wait(1000)
    if trailer_identities.code ~= 0 then
        vim.notify("Failed to get authors from trailers", vim.log.levels.DEBUG)
        return
    end

    for identity in assert(trailer_identities.stdout):gmatch("[^\n]+") do
        if not vim.list_contains(seen, identity) then
            table.insert(seen, identity)
            table.insert(global_identities, {label = identity})
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
    update_trailers_table()

    if params.context.cursor.row < 3 then
        -- The cursor is on the subject or gap between subject and body, where
        -- trailers are not allowed, so don't offer any completion candidates.
        callback()
        return
    end

    local co_author_prefix = params.context.cursor_before_line:match("^Co%-authored%-by: (.*)$")
    local sign_off_prefix = params.context.cursor_before_line:match("^Signed%-off%-by: (.*)$")
    if co_author_prefix or sign_off_prefix then
        update_identities_table(assert(co_author_prefix or sign_off_prefix))
        callback({items = global_identities, isIncomplete = true})
        return
    end

    if not params.context.cursor_before_line:match("^%S*$") then
        -- The cursor is not on a (possibly empty) word at the start of a line,
        -- so this can't be a trailer, so don't offer any completion candidates.
        callback()
        return
    end

    callback({items = global_trailers, isIncomplete = not updated_trailers})
end

return source
