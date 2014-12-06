#!/usr/bin/tclsh
set dir [file dirname [info script]]
lappend auto_path [file join $dir ".."]
package require nest

if { [llength $argv] != 1 } {
    puts "Usage: $argv0 message.nest"
    exit
}

::nest::conf::set_option output_format 5

set filename [lindex $argv 0]
set lang_nsp ::nest::data
set doc [source_tdom $filename $lang_nsp]
if { [::nest::debug::dom_p] } {
    puts [$doc asXML]
    set root [$doc documentElement]
}
$doc delete
