namespace eval ::nest::conf {

    namespace export set_option get_option

    variable debug_p 0
    variable dom_p 1
    variable output_format 1

    proc set_option {varname value} {
        set nsp [namespace current]
        variable ${nsp}::$varname
        set $varname $value
    }

    proc get_option {varname} {
        set nsp [namespace current]
        variable ${nsp}::$varname
        return [set $varname]
    }


}

