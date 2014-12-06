#!/usr/bin/tclsh
set dir [file dirname [info script]]
lappend auto_path [file join $dir ".."]
package require nest

proc util_readfile {filename} {
    set fp [open $filename]
    set data [read $fp]
    close $fp
    return $data
}

if { [llength $argv] != 1 } {
    puts "Usage: $argv0 message.nest"
    exit
}

::nest::conf::set_option output_format 0

set filename [lindex $argv 0]
set lang_nsp ::nest::data
set xml [source_tdom $filename $lang_nsp]
if { [::nest::debug::dom_p] } {

    puts [$xml asXML]

    set xslt [dom parse [util_readfile [file join $dir psql.xslt]]]
    set xmlroot [$xml documentElement]
    $xmlroot xslt $xslt resultDoc
    set resultroot [$resultDoc documentElement]
    set result [$resultDoc asXML]

}
$xml delete
$xslt delete
$resultDoc delete

puts $result

