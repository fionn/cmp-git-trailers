---@diagnostic disable-next-line: name-style-check
local source = {}

---@type lsp.CompletionItem[]
local symbol_table = {
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
        label = "On-behalf-of:",
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
        label = "Closes:",
        documentation = "Link to an issue this commit closes.\n\nSee https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword."
    },
    {
        label = "Fixes:",
        documentation = "Link to an issue this commit fixes.\n\nSee https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword."
    },
    {
        label = "skip-checks: true",
        documentation = "Skip CI/CD workflows in GitHub Actions.\n\nSee https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs."
    }
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
