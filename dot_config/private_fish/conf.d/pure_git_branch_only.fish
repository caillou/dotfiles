# Pure's git segment shows the branch name and nothing else.
#
# Pure's own _pure_prompt_git also runs `git status`, a stash count and an
# upstream ahead/behind check on every prompt. Behind Microsoft Defender every
# file open costs about 2 ms, so on a 25k-file worktree `git status` takes half
# a second per prompt and close to a minute whenever git has to re-hash the tree
# (2026-09-21: a 37 s hang on the first prompt of a new terminal). The branch is
# the one piece of git information worth having in the prompt.
#
# A function defined here wins over the copy fish would autoload from
# functions/, so fisher can update Pure without touching this override.

function _pure_prompt_git --description 'Print the git branch name only'
    if set --query pure_enable_git; and test "$pure_enable_git" != true
        return
    end

    type -q --no-functions git; or return

    test "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" = true; or return

    _pure_prompt_git_branch
end
