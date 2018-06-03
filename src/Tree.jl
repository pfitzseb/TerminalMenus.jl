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

    expanded::Bool
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
    Tree(head, children, false, [], length(children), 0, nothing, 0)
end

toggle(t::Tree) = (t.expanded = !t.expanded)

showmethod(T) = which(show, (IO, T))

getfield′(x, f) = isdefined(x, f) ? getfield(x, f) : Text("#undef")

function defaultrepr(x)
    fields = fieldnames(typeof(x))
    if isempty(fields)
        Text(string(typeof(x), "()"))
    else
        Tree(Text(string(typeof(x))),
                 [Tree(Text("$f → "), getfield′(x, f)) for f in fields])
    end
end

# This function must be implemented for all menu types. It defines what
#   happens when a user presses the Enter key while the menu is open.
# If this function returns true, `request()` will exit.
function pick(t::Tree, cursor::Int)
    child = t.children[cursor]
    child isa Tree && toggle(child)

    return false
end

# NECESSARY FUNCTIONS
# These functions must be implemented for all subtypes of AbstractMenu
######################################################################

# This function must be implemented for all menu types. It defines what
#   happends when a user cancels ('q' or ctrl-c) a menu. `request()` will
#   always exit after calling this function.
cancel(t::Tree) = nothing

# This function must be implemented for all menu types. It should return
#   a list of strings to be displayed as options in the current page.
function options(t::Tree)
    fill("", length(t.children))
end

const INDENTSIZE = 2

printIndent(buf::IOBuffer, level) = print(buf, " "^(level*INDENTSIZE))

function printTreeChild(buf::IOBuffer, child::Tree, cur::Bool, term_width::Int; level::Int = 0)
    if child.expanded
        cur ? print(buf, "[v] ") : print(buf, " v  ")
        # print Tree with additional nesting, but without an active cursor
        # init=true assures that the Tree printing doesn't mess with anything
        printMenu(buf, child, 0; init=true, level = level + 1)
    else
        cur ? print(buf, "[>] ") : print(buf, " >  ")
        # only print header
        print(buf, child.head)
    end
end

function writeChild(buf::IOBuffer, t::Tree, idx::Int, cur::Bool, term_width::Int; level::Int = 0)
    tmpbuf = IOBuffer()

    child = t.children[idx]

    if child isa Tree
        printTreeChild(tmpbuf, child, cur, term_width, level = level)
    else
        # if there's a specially designed show method we fall back to that
        if showmethod(typeof(child)) ≠ showmethod(Any)
            cur ? print(buf, "[ ] ") : print(buf, "    ")
            printIndent(tmpbuf, level)
            print(tmpbuf, Text(io -> show(IOContext(io, limit = true), MIME"text/plain"(), child)))
        else
            d = defaultrepr(child)
            if d isa Tree
                printTreeChild(tmpbuf, d, cur, term_width, level = level)
            else
                printIndent(tmpbuf, level)
                print(tmpbuf, d)
            end
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

function printMenu(out, m::Tree, cursor::Int; init::Bool=false, level=0)
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
    print(buf, m.head)
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


        writeChild(buf, m, i, i == cursor, term_width, level=level)

        # dont print an \r\n on the last line
        i != (m.pagesize+m.pageoffset) && print(buf, "\r\n")
    end

    str = String(take!(buf))

    m.lastHeight = count(c -> c == '\n', str)

    print(out, str)
end
