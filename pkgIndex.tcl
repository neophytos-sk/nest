set dir [file dirname [info script]]
package ifneeded nest 0.2 "
    source [file join $dir tcl dom-scripting.tcl]
    source [file join $dir tcl nest-lang.tcl]
"
