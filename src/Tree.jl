# > TypeFoo
#    >  Child1
#    >  Child2
#   [>] Child3
#    v  Child4
#      Child41
#      Child42

export @ishow

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

    cursor
end

# mutable struct SubTree <: AbstractTree
#     head
#     children
#
#     expanded
#     options
# end

function Tree(head, children)
    Tree(head, children, false, [], length(children), 0, nothing, 0, 0)
end

toggle(t::Tree) = (t.expanded = !t.expanded)

showmethod(T) = which(show, (IO, T))

getfield′(x, f) = isdefined(x, f) ? getfield(x, f) : Text("#undef")

function defaultrepr(x; smethod=false)
    if smethod && showmethod(typeof(x)) ≠ showmethod(Any)
        b = IOBuffer()
        print(b, Text(io -> show(IOContext(io, limit = true), MIME"text/plain"(), x)))
        Text(String(take!(b)))
    else
        fields = fieldnames(typeof(x))

        if isempty(fields)
            Tree(string(typeof(x), "()"), [])
        else
            Tree(string(typeof(x)),
                 [Tree(string(f), [defaultrepr(getfield′(x, f), smethod=true)]) for f in fields])
        end
    end
end

# This function must be implemented for all menu types. It defines what
#   happens when a user presses the Enter key while the menu is open.
# If this function returns true, `request()` will exit.
function pick(t::Tree, currentItem)
    if currentItem isa Tree
        toggle(currentItem)
    end

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

printIndent(buf::IOBuffer, level) = print(buf, " "^(level))

indent(level) = "  "

function printTreeChild(buf::IOBuffer, child::Tree, cursor, term_width::Int; level::Int = 0)
    cur = cursor == -1
    if child.expanded
        cur ? print(buf, "[▼] ") : print(buf, " ▼  ")
        # print Tree with additional nesting, but without an active cursor
        # init=true assures that the Tree printing doesn't mess with anything
        cursor = printMenu′(buf, child, cursor; init=true, level = level)
    else
        cur ? print(buf, "[▶] ") : print(buf, " ▶  ")
        # only print header
        print(buf, child.head)
    end

    cursor
end

macro ishow(x)
    :(ishow($(esc(x))))
end

function ishow(x)
    t = if showmethod(typeof(x)) ≠ showmethod(Any)
        b = IOBuffer()
        print(b, Text(io -> show(IOContext(io, limit = true), MIME"text/plain"(), x)))
        strs = split(String(take!(b)), '\n')
        if length(strs) > 1
            Tree(strs[1], [Text(join(strs[2:end], '\n'))])
        else
            Tree(strs[1], [])
        end
    else
        defaultrepr(x)
    end
    request(t)
end

function writeChild(buf::IOBuffer, t::Tree, idx::Int, cursor, term_width::Int; level::Int = 0)
    tmpbuf = IOBuffer()

    child = t.children[idx]

    cursor -= 1
    cur = cursor == -1
    if child isa Tree
        cursor = printTreeChild(tmpbuf, child, cursor, term_width, level = level)
    else
        # if there's a specially designed show method we fall back to that
        if showmethod(typeof(child)) ≠ showmethod(Any)
            cur ? print(buf, "[ ] ") : print(buf, "    ")
            b = IOBuffer()
            print(b, Text(io -> show(IOContext(io, limit = true), MIME"text/plain"(), child)))
            s = join(split(String(take!(b)), '\n'), "\n"*indent(level))
            print(tmpbuf, s)
        else
            d = defaultrepr(child)
            if d isa Tree
                cursor = printTreeChild(tmpbuf, d, cursor, term_width, level = level)
            else
                b = IOBuffer()
                print(b, d)
                s = join(split(String(take!(b)), '\n'), "\n"*indent(level))
                print(tmpbuf, s)
            end
        end
    end

    str = String(take!(tmpbuf))

    str = join(split(str, '\n'), "\n"*indent(level))

    print(buf, str)

    cursor
end


# OPTIONAL FUNCTIONS
# These functions do not need to be implemented for all Menu types
##################################################################


# If `header()` is defined for a specific menu type, display the header
#  above the menu when it is rendered to the screen.
header(t::Tree) = ""

# If `keypress()` is defined for a specific menu type, send any
#   non-standard keypres event to this function. If the function returns
#   true, `request()` will exit.
keypress(m::AbstractMenu, i::UInt32) = false

function printMenu′(out, m::Tree, cursor; init::Bool=false, level=0)
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

    term_width = Base.Terminals.width(TerminalMenus.terminal)

    # print header
    println(buf, m.head)

    for i in 1:length(m.children)
        print(buf, "\x1b[2K")

        cursor = writeChild(buf, m, i, cursor, term_width, level=level+1)

        # dont print an \r\n on the last line
        i != (m.pagesize+m.pageoffset) && print(buf, "\r\n")
    end

    str = String(take!(buf))

    m.lastHeight = count(c -> c == '\n', str)

    print(out, str)
    cursor
end

function findItem(t::Tree, cursor; )
    i = nothing
    for c in t.children
        if cursor == 0
            return c, cursor
        end

        cursor -= 1

        if c isa Tree && c.expanded
            i, cursor = findItem(c, cursor)
        end

        if i ≠ nothing
            return i, cursor
        end
    end
    return i, cursor
end

function request(term::Base.Terminals.TTYTerminal, m::Tree)
    cursor = 0

    menu_header = header(m)
    if !CONFIG[:supress_output] && menu_header != ""
        println(term.out_stream, menu_header)
    end

    printMenu′(term.out_stream, m, cursor, init=true)

    raw_mode_enabled = enableRawMode(term)
    raw_mode_enabled && print(term.out_stream, "\x1b[?25l") # hide the cursor
    try
        while true
            c = readKey(term.in_stream)

            currentItem, _ = findItem(m, cursor)

            if c == Int(ARROW_UP)
                if cursor > 0
                    cursor -= 1
                end
            elseif c == Int(ARROW_DOWN)
                cursor += 1
            elseif c == 13 # <enter>
                # will break if pick returns true
                currentItem isa Tree && toggle(currentItem)
            elseif c == UInt32('q')
                cancel(m)
                break
            elseif c == 3 # ctrl-c
                cancel(m)
                if CONFIG[:ctrl_c_interrupt]
                    throw(InterruptException())
                else
                    break
                end
            else
                # will break if keypress returns true
                keypress(m, c) && break
            end

            printMenu′(term.out_stream, m, cursor)
        end
    finally
        # always disable raw mode even even if there is an
        #  exception in the above loop
        if raw_mode_enabled
            print(term.out_stream, "\x1b[?25h") # unhide cursor
            disableRawMode(term)
        end
    end
    println(term.out_stream)

    return m.selected
end

function toggleall(t::Tree, expand)
    for child in t.children
        if child isa Tree
            child.expanded = expand
            toggleall(child, expand)
        end
    end
end


function keypress(t::Tree, key::UInt32)
    if key == UInt32('e') || key == UInt32('E')
        toggleall(t, true)
    elseif key == UInt32('c') || key == UInt32('C')
        toggleall(t, false)
    end
    false # don't break
end
