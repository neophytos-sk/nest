namespace eval ::nest::debug {
    
    namespace export *

    variable debug_p 0
    variable dom_p 1

    proc debug_p {} {
        variable debug_p
        return $debug_p
    }

    proc debug_on {} {
        variable debug_p
        set debug_p 1
    }

    proc debug_off {} {
        variable debug_p
        set debug_p 0
    }

    proc dom_p {} {
        variable dom_p
        return $dom_p
    }
    
    proc caller {} {
        array set frame [info frame [expr { [info frame] - 2 }]]
        return $frame(proc)
    }

    proc log {msg {force_p 0}} {
        if {[debug_p] || ${force_p} } {
            puts [format "%-25s %s" [caller] ${msg}]
        }
    }

    proc dump {} {
        variable ::nest::core::stack_nest
        variable ::nest::core::stack_fwd
        variable ::nest::core::stack_mode
        variable ::nest::core::stack_eval
        variable ::nest::core::eval_path
        
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
        append msg $nl $sp "stack_nest=[list $stack_nest]"
        append msg $nl $sp "stack_fwd=[list $stack_fwd]"
        append msg $nl $sp "stack_mode=[list $stack_mode]"
        append msg $nl $sp "stack_eval=[list $stack_eval]"
        append msg $nl $sp "eval_path=${eval_path}"
        append msg $nl $sp "vars${nl}${sp}${sp}[join $vars "\n${sp}${sp}"]"

        log $msg true

    }

    proc error {msg {info ""} {code ""}} {
        uplevel dump
        ::error ${msg} {*}${info} {*}${code}
    }

    proc time_cps {script {iters "10000"}} {
        set s [time $script $iters]
        set cps [expr {round(1/([lindex $s 0]/1e6))}]
        puts "$cps calls per second of: $script \n"
    }


}
