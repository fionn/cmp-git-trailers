# cmp-git-trailers

Completion source for Git trailers. This covers some of the common trailers that I use; it's not intended to be exhaustive (e.g. we don't seek to cover https://lore.kernel.org/git/60ad75ac7ffca_2ae08208b@natae.notmuch/), although contributions are welcome.

# Installation

Install this plugin, then add it as a completion source, either generally (it will only offer completion candidates for commit messages anyway) or specifically for commit messages with

```lua
cmp.setup.filetype("gitcommit", {
    ---@type cmp.SourceConfig[]
    sources = cmp.config.sources {
        {name = "git_trailers"}
    }
})
```
or similar.
