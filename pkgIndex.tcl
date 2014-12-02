set dir [file dirname [info script]]
package ifneeded nest 1.5 "
    source [file join $dir tcl dom-scripting.tcl]
    source [file join $dir tcl nest-debug.tcl]
    source [file join $dir tcl nest-core.tcl]
    source [file join $dir tcl nest-lang.tcl]
"
