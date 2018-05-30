# > TypeFoo
#    >  Child1
#    >  Child2
#   [>] Child3
#    v  Child4
#      Child41
#      Child42

abstract type AbstractTree <: AbstractMenu end

mutable struct Tree <: AbstractTree
    head
    children::Vector{Any}

    expanded::Set{Int}
    options::Vector{String}

    pagesize::Int
    pageoffset::Int

    selected
    lastHeight::Int
end

# mutable struct SubTree <: AbstractTree
#     head
#     children
#
#     expanded
#     options
# end

function Tree(head, children)
    Tree(head, children, Set{Int}(), [], length(children), 0, nothing, 0)
end

# This function must be implemented for all menu types. It defines what
#   happens when a user presses the Enter key while the menu is open.
# If this function returns true, `request()` will exit.
function pick(t::Tree, cursor::Int)
    if cursor in t.expanded
        delete!(t.expanded, cursor)
        # delete!(t.selected, cursor)
    else
        push!(t.expanded, cursor)
        # push!(t.selected, cursor)
    end

    return false
end

# NECESSARY FUNCTIONS
# These functions must be implemented for all subtypes of AbstractMenu
######################################################################

# This function must be implemented for all menu types. It defines what
#   happends when a user cancels ('q' or ctrl-c) a menu. `request()` will
#   always exit after calling this function.
cancel(t::Tree) = empty!(t.expanded)

# This function must be implemented for all menu types. It should return
#   a list of strings to be displayed as options in the current page.
function options(t::Tree)
    fill("", length(t.children))
end

# This function must be implemented for all menu types. It should write
#   the option at index `idx` to the buffer. If cursor is `true` it
#   should also display the cursor
function writeLine(buf::IOBuffer, t::Tree, idx::Int, cur::Bool, term_width::Int; indent::Int=0)
    tmpbuf = IOBuffer()

    child = t.children[idx]

    if child isa Tree
        if idx in t.expanded
            print(tmpbuf, cur ? "[v] " : " v  ")
            print(tmpbuf, child.head)
            print(tmpbuf, "\n\r")
            printMenu(tmpbuf, child, 0, init=true, indent=indent+2)
        else
            print(tmpbuf, cur ? "[>] " : " >  ")
            print(tmpbuf, child.head)
        end
    else
        print(tmpbuf, cur ? "[ ] " : "    ")
        strs = split(sprint(io -> show(IOContext(io, limit = true), MIME"text/plain"(), child)), '\n')
        if length(strs) > 1
            printMenu(tmpbuf, Tree(strs[1], [join(strs, "\n")]), 0, init=true, indent=indent+2)
        else
            print(tmpbuf, strs[1])
        end
    end

    print(buf, String(take!(tmpbuf)))
end


# OPTIONAL FUNCTIONS
# These functions do not need to be implemented for all Menu types
##################################################################


# If `header()` is defined for a specific menu type, display the header
#  above the menu when it is rendered to the screen.
header(t::Tree) = t.head

# If `keypress()` is defined for a specific menu type, send any
#   non-standard keypres event to this function. If the function returns
#   true, `request()` will exit.
keypress(m::AbstractMenu, i::UInt32) = false

function printMenu(out, m::Tree, cursor::Int; init::Bool=false, indent=0)
    CONFIG[:supress_output] && return

    buf = IOBuffer()

    if init
        m.pageoffset = 0
    else
        # move cursor to beginning of current menu
        print(buf, "\x1b[999D\x1b[$(m.lastHeight)A")
        # clear display until end of screen
        print(buf, "\x1b[0J")
    end

    for i in (m.pageoffset+1):(m.pageoffset + m.pagesize)
        print(buf, "\x1b[2K")

        if i == m.pageoffset+1 && m.pageoffset > 0
            # first line && scrolled past first entry
            print(buf, CONFIG[:up_arrow])
        elseif i == m.pagesize+m.pageoffset && i != length(options(m))
            # last line && not last option
            print(buf, CONFIG[:down_arrow])
        else
            # non special line
            print(buf, " ")
        end

        term_width = Base.Terminals.width(TerminalMenus.terminal)

        print(buf, " "^indent)
        writeLine(buf, m, i, i == cursor, term_width, indent=indent)

        # dont print an \r\n on the last line
        i != (m.pagesize+m.pageoffset) && print(buf, "\r\n")
    end

    str = String(take!(buf))

    m.lastHeight = count(c -> c == '\n', str)

    print(out, str)
end
