namespace eval ::nest::debug {
    
    namespace export *

    variable debug_p 0

    proc debug_p {} {
        variable debug_p
        return $debug_p
    }
    
    proc caller {} {
        array set frame [info frame [expr { [info frame] - 2 }]]
        return $frame(proc)
    }

    if { [debug_p] } {
        proc log {msg} {
            puts [format "%-25s %s" [caller] ${msg}]
        }
    } else {
        proc log {msg} {}
    }

    proc dump {} {
        variable ::nest::lang::stack_ctx
        variable ::nest::lang::stack_fwd
        variable ::nest::lang::stack_mode
        variable ::nest::lang::stack_eval
        variable ::nest::lang::eval_path
        
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
        append msg $nl $sp "stack_eval=[list $stack_eval]"
        append msg $nl $sp "eval_path=${eval_path}"
        append msg $nl $sp "vars${nl}${sp}${sp}[join $vars "\n${sp}${sp}"]"

        log $msg

    }

    proc error {msg {info ""} {code ""}} {
        dump
        ::error ${msg} {*}${info} {*}${code}
    }

    proc time_cps {script {iters "10000"}} {
        set s [time $script $iters]
        set cps [expr {round(1/([lindex $s 0]/1e6))}]
        puts "$cps calls per second of: $script \n"
    }


}
