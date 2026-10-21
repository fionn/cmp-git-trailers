# cmp-git-trailers

Completion source for Git trailers.

Trailers are sourced from:
* a small built-in list of common trailers,
* the previous hundred commits (if available, asynchronously).

There are many somewhat popular trailers (see e.g. [_The top 1% of commit trailers_](https://lore.kernel.org/git/60ad75ac7ffca_2ae08208b@natae.notmuch/)). We don't intend to cover these, although contributions for useful trailers are welcome.

We also provide completion candidates for `Co-authored-by` values, sourced from previous commit authors.

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
