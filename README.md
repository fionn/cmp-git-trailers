# cmp-git-trailers

Completion source for Git trailers.

Trailers are sourced from:
* a small built-in list of common trailers,
* the previous hundred commits (if available, asynchronously).

There are many somewhat popular trailers (see e.g. [_The top 1% of commit trailers_](https://lore.kernel.org/git/60ad75ac7ffca_2ae08208b@natae.notmuch/)). We don't intend to cover these, although contributions by humans for useful trailers are welcome.

We also provide completion candidates for `Co-authored-by` values, sourced from previous commit authors and existing `Co-authored-by` values.

## Installation

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

## Demo

<div align="center">
    <a href="https://asciinema.org/a/QOAbXS9oWO4t5SAF"><img width="600" alt="Example Git trailer and co-author completion using fionn/cmp-git-trailers" src="https://github.com/user-attachments/assets/f136547e-2873-403a-83c1-2028859f1f0d"></a>
</div>
