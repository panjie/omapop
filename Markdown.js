.pragma library

// Small CommonMark-flavoured renderer for the result card. Qt's built-in
// Markdown importer cannot be styled, so we produce a restrained HTML subset
// that QTextDocument can lay out: coloured headings, code with a surface,
// tables, quotes and links. Raw HTML is always escaped.

var TOKEN_OPEN = "\u0000"
var TOKEN_CLOSE = "\u0001"

function escapeHtml(s) {
    return String(s === undefined || s === null ? "" : s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
}

function escapeAttr(s) {
    return escapeHtml(s).replace(/"/g, "&quot;")
}

function safeUrl(url) {
    var u = String(url || "").replace(/^\s+|\s+$/g, "")
    return /^(https?:|mailto:)/i.test(u) ? u : ""
}

function styleSpan(style, html) {
    return "<span style=\"" + style + "\">" + html + "</span>"
}

function inline(text, p, allowLinks) {
    var tokens = []

    function keep(html) {
        tokens.push(html)
        return TOKEN_OPEN + (tokens.length - 1) + TOKEN_CLOSE
    }

    var s = String(text === undefined || text === null ? "" : text)

    // Code spans first: their contents must never be parsed as Markdown.
    s = s.replace(/(`+)([^`]*?)\1/g, function (_, ticks, code) {
        return keep(styleSpan("font-family:monospace;color:" + p.codeText + ";background-color:" + p.codeBg,
            escapeHtml(code.replace(/^\s+|\s+$/g, ""))))
    })

    if (allowLinks) {
        s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, function (_, alt) {
            return keep(inline(alt, p, false))
        })
        s = s.replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, function (_, label, url) {
            var href = safeUrl(url)
            var body = inline(label, p, false)
            if (!href)
                return keep(body)
            return keep("<a href=\"" + escapeAttr(href) + "\" style=\"color:" + p.link + "\">" + body + "</a>")
        })
        s = s.replace(/<(https?:\/\/[^>\s]+)>/g, function (match, url) {
            var href = safeUrl(url)
            return href ? keep("<a href=\"" + escapeAttr(href) + "\" style=\"color:" + p.link + "\">" + escapeHtml(url) + "</a>") : match
        })
    }

    s = s.replace(/\\([\\`*_{}\[\]()#+\-.!|>~])/g, function (_, ch) {
        return keep(escapeHtml(ch))
    })
    s = escapeHtml(s)

    s = s.replace(/\*\*\*([^*]+)\*\*\*/g, "<b><i>$1</i></b>")
    s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    s = s.replace(/(^|[^\w])__([^_]+)__(?=[^\w]|$)/g, "$1<b>$2</b>")
    s = s.replace(/\*([^*]+)\*/g, "<i>$1</i>")
    s = s.replace(/(^|[^\w])_([^_]+)_(?=[^\w]|$)/g, "$1<i>$2</i>")
    s = s.replace(/~~([^~]+)~~/g, "<s>$1</s>")

    s = s.replace(/\u0000(\d+)\u0001/g, function (_, n) {
        return tokens[Number(n)]
    })
    return s
}

function listItem(line) {
    var m = line.match(/^(\s*)([-+*]|\d+[.)])\s+(.*)$/)
    if (!m)
        return null
    return {
        indent: m[1].length,
        ordered: /\d/.test(m[2]),
        number: parseInt(m[2], 10) || 1,
        text: m[3]
    }
}

function fence(line) {
    var m = line.match(/^(\s{0,3})(`{3,}|~{3,})(.*)$/)
    return m ? { marker: m[2], language: m[3].replace(/^\s+|\s+$/g, "") } : null
}

function heading(line) {
    var m = line.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/)
    return m ? { level: m[1].length, text: m[2] } : null
}

function horizontalRule(line) {
    return /^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$/.test(line)
}

function setext(line) {
    if (/^\s{0,3}=+\s*$/.test(line))
        return 1
    if (/^\s{0,3}-{2,}\s*$/.test(line))
        return 2
    return 0
}

function tableSeparator(line) {
    if (line.indexOf("-") < 0 || line.indexOf("|") < 0)
        return false
    return /^\s*\|?[\s:|-]+\|[\s:|-]*$/.test(line)
}

function splitRow(line) {
    var s = line.replace(/^\s+|\s+$/g, "")
    if (s.charAt(0) === "|")
        s = s.slice(1)
    if (s.charAt(s.length - 1) === "|")
        s = s.slice(0, -1)
    return s.split("|").map(function (cell) { return cell.replace(/^\s+|\s+$/g, "") })
}

function alignments(line) {
    return splitRow(line).map(function (cell) {
        var left = cell.charAt(0) === ":"
        var right = cell.charAt(cell.length - 1) === ":"
        if (left && right) return "center"
        if (right) return "right"
        if (left) return "left"
        return ""
    })
}

function tableAt(lines, i) {
    return i + 1 < lines.length && lines[i].indexOf("|") >= 0 && tableSeparator(lines[i + 1])
}

function isBlockStart(lines, i) {
    if (i >= lines.length)
        return true
    var line = lines[i]
    if (/^\s*$/.test(line) || heading(line) || fence(line) || horizontalRule(line))
        return true
    if (/^\s{0,3}>/.test(line) || listItem(line))
        return true
    return tableAt(lines, i)
}

function closeItem(out, stack) {
    if (!stack.length)
        return
    var top = stack[stack.length - 1]
    if (top.itemOpen) {
        out.push("</li>")
        top.itemOpen = false
    }
}

function closeList(out, stack) {
    var top = stack.pop()
    if (top.itemOpen)
        out.push("</li>")
    out.push(top.ordered ? "</ol>" : "</ul>")
}

function closeListsTo(out, stack, indent) {
    while (stack.length && stack[stack.length - 1].indent > indent)
        closeList(out, stack)
}

function openList(out, stack, info) {
    stack.push({ indent: info.indent, ordered: info.ordered, itemOpen: false })
    if (info.ordered)
        out.push(info.number === 1 ? "<ol>" : "<ol start=\"" + info.number + "\">")
    else
        out.push("<ul>")
}

function renderListLine(out, stack, info, p) {
    closeListsTo(out, stack, info.indent)
    var top = stack.length ? stack[stack.length - 1] : null
    if (!top || top.indent < info.indent) {
        openList(out, stack, info)
    } else if (top.indent === info.indent && top.ordered !== info.ordered) {
        closeList(out, stack)
        openList(out, stack, info)
    } else {
        closeItem(out, stack)
    }

    var text = info.text
    if (/^\[[ xX]\]\s+/.test(text)) {
        var checked = !/^\[ \]/.test(text)
        text = text.replace(/^\[[ xX]\]\s+/, "")
        text = styleSpan("color:" + p.heading, checked ? "\u2611" : "\u2610") + " " + inline(text, p, true)
    } else {
        text = inline(text, p, true)
    }
    out.push("<li>" + text)
    stack[stack.length - 1].itemOpen = true
}

function toHtml(source, p) {
    var lines = String(source || "")
        .replace(/\r\n?/g, "\n")
        .replace(/\t/g, "    ")
        .split("\n")
    var out = []
    var listStack = []
    var i = 0
    var base = Math.max(1, Math.round(Number(p.baseSize) || 13))
    var gap = Math.max(4, Math.round(Number(p.paragraphGap) || 8))

    function flushLists() {
        closeListsTo(out, listStack, -1)
    }

    while (i < lines.length) {
        var line = lines[i]

        if (/^\s*$/.test(line)) {
            flushLists()
            i++
            continue
        }

        var f = fence(line)
        if (f) {
            flushLists()
            var code = []
            i++
            while (i < lines.length) {
                var end = fence(lines[i])
                if (end && end.marker.charAt(0) === f.marker.charAt(0) && end.marker.length >= f.marker.length)
                    break
                code.push(lines[i])
                i++
            }
            if (i < lines.length)
                i++
            out.push("<pre style=\"background-color:" + p.codeBg + ";color:" + p.text
                + ";padding:" + Math.round(gap * 1.25) + "px;margin-top:0;margin-bottom:"
                + gap + "px;font-family:monospace;white-space:pre-wrap\">"
                + escapeHtml(code.join("\n")) + "</pre>")
            continue
        }

        var h = heading(line)
        if (h) {
            flushLists()
            out.push(headingHtml(h.level, inline(h.text, p, true), p, base, gap))
            i++
            continue
        }

        if (i + 1 < lines.length && setext(lines[i + 1])) {
            flushLists()
            out.push(headingHtml(setext(lines[i + 1]), inline(line, p, true), p, base, gap))
            i += 2
            continue
        }

        if (horizontalRule(line)) {
            flushLists()
            out.push("<hr style=\"color:" + p.border + ";margin-top:" + gap + "px;margin-bottom:" + gap + "px\">")
            i++
            continue
        }

        if (/^\s{0,3}>/.test(line)) {
            flushLists()
            var quoted = []
            while (i < lines.length && /^\s{0,3}>/.test(lines[i])) {
                quoted.push(lines[i].replace(/^\s{0,3}>\s?/, ""))
                i++
            }
            var bar = styleSpan("color:" + p.heading, "\u258e")
            var text = quoted.map(function (q) {
                return q.length ? bar + " " + inline(q, p, true) : bar
            }).join("<br>")
            out.push("<p style=\"margin-top:0;margin-bottom:" + gap + "px;color:" + p.muted + "\">" + text + "</p>")
            continue
        }

        if (tableAt(lines, i)) {
            flushLists()
            var header = splitRow(line)
            var aligns = alignments(lines[i + 1])
            i += 2
            var rows = []
            while (i < lines.length && lines[i].indexOf("|") >= 0 && !/^\s*$/.test(lines[i])) {
                rows.push(splitRow(lines[i]))
                i++
            }
            var cell = "padding:6px 8px;"
            var html = "<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"1\" bordercolor=\""
                + escapeAttr(p.border) + "\" style=\"margin-top:0;margin-bottom:" + gap + "px\">"
            html += "<tr>"
            for (var c = 0; c < header.length; c++)
                html += "<th align=\"" + (aligns[c] || "left") + "\" style=\"" + cell + "background-color:" + p.blockBg
                    + ";color:" + p.heading + "\">" + inline(header[c], p, true) + "</th>"
            html += "</tr>"
            for (var r = 0; r < rows.length; r++) {
                html += "<tr>"
                for (var k = 0; k < header.length; k++)
                    html += "<td align=\"" + (aligns[k] || "left") + "\" style=\"" + cell + "\">"
                        + inline(rows[r][k] === undefined ? "" : rows[r][k], p, true) + "</td>"
                html += "</tr>"
            }
            out.push(html + "</table>")
            continue
        }

        var info = listItem(line)
        if (info) {
            renderListLine(out, listStack, info, p)
            i++
            continue
        }

        if (listStack.length) {
            var lead = line.match(/^\s*/)[0].length
            var top = listStack[listStack.length - 1]
            if (lead >= top.indent + 2) {
                out.push("<br>" + inline(line.replace(/^\s+|\s+$/g, ""), p, true))
                i++
                continue
            }
            flushLists()
        }

        var para = []
        while (i < lines.length && !isBlockStart(lines, i)) {
            if (i + 1 < lines.length && setext(lines[i + 1]))
                break
            para.push(inline(lines[i].replace(/^\s+|\s+$/g, ""), p, true))
            i++
        }
        if (para.length)
            out.push("<p style=\"margin-top:0;margin-bottom:" + gap + "px\">" + para.join("<br>") + "</p>")
    }

    flushLists()
    return out.join("\n")
}

function headingHtml(level, text, p, base, gap) {
    var size = level === 1 ? Math.round(base * 1.6)
        : level === 2 ? Math.round(base * 1.35)
        : level === 3 ? Math.round(base * 1.15)
        : base + 1
    var top = level === 1 ? Math.round(base * 1.3) : level === 2 ? Math.round(base * 1.1) : Math.round(base * 0.8)
    var bottom = Math.round(base * 0.35)
    var color = level <= 3 ? p.heading : p.text
    return "<h" + level + " style=\"color:" + color + ";font-size:" + size + "px;margin-top:"
        + (top - gap) + "px;margin-bottom:" + bottom + "px\">" + text + "</h" + level + ">"
}
