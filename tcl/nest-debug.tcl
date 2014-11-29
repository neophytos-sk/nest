namespace eval ::nest::debug {
    
    namespace export *

    variable debug 0

    proc debug_p {} {
        variable debug
        return $debug
    }

    proc caller {} {
        array set frame [info frame [expr { [info frame] - 2 }]]
        return $frame(proc)
    }

    proc log {msg {force_p false}} {
        variable debug
        if {[debug_p] || $force_p } {
            puts [format "%-25s %s" [caller] ${msg}]
        }
    }

    proc dump {} {
        variable ::nest::lang::stack_ctx
        variable ::nest::lang::stack_fwd
        variable ::nest::lang::stack_mode
        
        set vars [list]
        foreach varname [uplevel {info vars}] {
            upvar $varname localCopy
            if { [array exists localCopy] } {
                lappend vars "$varname = [array get localCopy]"
            } else {
                lappend vars "$varname = $localCopy"
            }
        }

        set nl "\n"
        set sp "  "
        set msg ""
        append msg $nl $sp "stack_ctx=[list $stack_ctx]"
        append msg $nl $sp "stack_fwd=[list $stack_fwd]"
        append msg $nl $sp "stack_mode=[list $stack_mode]"
        append msg $nl $sp "vars${nl}${sp}${sp}[join $vars "\n${sp}${sp}"]"

        log $msg true

    }

}
