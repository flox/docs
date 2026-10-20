-- mdx-compat.lua — pandoc filter for sync-man-pages.sh
--
-- Rewrites constructs that pandoc's gfm writer emits in forms MDX cannot
-- parse, so the man page sources in flox/flox can stay plain pandoc markdown.

-- The gfm writer always emits a link whose text is its URL as an autolink
-- (<https://...>), which MDX parses as a JSX tag. Write an explicit link.
function Link(el)
  if pandoc.utils.stringify(el.content) == el.target then
    return pandoc.RawInline('gfm', '[' .. el.target .. '](' .. el.target .. ')')
  end
end

-- The gfm writer emits an unlabelled code block as indented code, which MDX
-- does not support (a `{` in the body is then parsed as an expression).
-- Labelling it makes the writer emit a fence.
function CodeBlock(el)
  if #el.classes == 0 then
    el.classes = { 'text' }
  end
  return el
end
