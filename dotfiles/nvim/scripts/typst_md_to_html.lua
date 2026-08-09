-- scripts/typst_md_to_html.lua
package.path = package.path .. ";" .. vim.fn.expand("~/.config/nvim/lua/scripts/?.lua")
local typst = require("typst_converter")

local input_path = arg[1]
local output_path = arg[2]

local f = io.open(input_path, "r")
if not f then
  return
end
local content = f:read("*all")
f:close()

-- 1. CONVERT TYPST MATH TO LATEX
-- We replace $...$ before markdown parsing to protect the math
local processed = content
  :gsub("%$%$(.-)%$%$", function(inner)
    return "$$" .. typst.typst_to_latex(inner) .. "$$"
  end)
  :gsub("%$([^%$]+)%$", function(inner)
    return "$" .. typst.typst_to_latex(inner) .. "$"
  end)

-- 2. GENERATE HTML (GitHub Dark Mode + KaTeX)
local html_template = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Typst Preview</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.2.0/github-markdown-dark.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css">
    
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/contrib/auto-render.min.js"></script>

    <style>
        body { background-color: #0d1117; margin: 0; padding: 0; }
        .markdown-body {
            box-sizing: border-box;
            min-width: 200px;
            max-width: 900px;
            margin: 0 auto;
            padding: 45px;
        }
        /* Make math pop slightly in dark mode */
        .katex { color: #e6edf3; } 
    </style>
</head>
<body class="markdown-body">
    <div id="raw-content" style="display:none;">]] .. processed .. [[</div>
    <div id="render-target"></div>

    <script>
        document.addEventListener("DOMContentLoaded", function() {
            const raw = document.getElementById('raw-content').textContent;
            
            // A. Render Markdown Structure (Headings, Lists, etc.)
            document.getElementById('render-target').innerHTML = marked.parse(raw);

            // B. Render Math (KaTeX)
            renderMathInElement(document.getElementById('render-target'), {
                delimiters: [
                    {left: "$$", right: "$$", display: true},
                    {left: "$", right: "$", display: false}
                ],
                throwOnError : false,
                trust: true
            });
        });
    </script>
</body>
</html>]]

local out = io.open(output_path, "w")
if out then
  out:write(html_template)
  out:close()
end
