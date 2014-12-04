package require tdom

package provide nest 1.5

define_lang ::nest::lang {

    # namespace import ::nest::core::* 

    # =========
    # stack_nest
    # =========
    #
    # each context is a pair of ctx_tag, and ctx_name
    #
    # EXAMPLE 1:
    #
    # struct slot {
    #     varchar name
    #     varchar type
    #     varchar default
    #     -> bool optional_p = false
    #     varchar container_type
    #     varchar subtype
    # }
    # 
    # stack_nest = {base_type bool} {meta struct}
    #
    # EXAMPLE 2:
    # 
    # struct email {
    #   varchar name
    #   -> varchar address
    # }
    #
    # stack_nest = {base_type varchar} {meta struct}

    variable stack_nest [list]
    variable stack_fwd [list]
    variable stack_mode [list {inst}]  ;# default mode is {inst}
    variable stack_eval [list]

    variable eval_path ""

    array set alias [list]
    array set forward [list]
    array set dispatcher [list]
    array set typeof [list]
 
    proc array_setter {arrayname name value} {
        variable ${arrayname}
        set ${arrayname}(${name}) ${value}
    }
    proc array_getter {arrayname name} {
        variable ${arrayname}
        set ${arrayname}(${name})
    }
    proc array_exister {arrayname name} {
        variable ${arrayname}
        info exists ${arrayname}(${name})
    }

    proc stack_push {varname value} {
        variable ${varname}
        set ${varname} [linsert [set ${varname}] 0 ${value}]
    }
    proc stack_pop {varname} {
        variable ${varname}
        set ${varname} [lreplace [set ${varname}] 0 0]
    }
    proc stack_top {varname} { 
        variable ${varname}
        lindex [set ${varname}] 0
    }
    proc stack_with {varname value args} {
        stack_push ${varname} ${value}
        set result [uplevel ${args}]
        stack_pop ${varname}
        return ${result}
    }

    proc {with_eval} {name args} {
        variable eval_path
        set old_eval_path ${eval_path}
        set eval_path [join [concat ${eval_path} ${name}] {.}]
        push_eval ${name}
        set result [uplevel ${args}]
        pop_eval
        set eval_path ${old_eval_path}
        return ${result}
    }

    proc {eval_path} {} {
        variable {eval_path}
        return ${eval_path}
    }

    proc {gen_eval_name} {name} {
        variable {eval_path}
        join [concat ${eval_path} ${name}] {.}
    }


    # Wow!!!
    set nsp [namespace current]
    set {aliasCmd} {lambda {nsp name arg0 args} {
        interp_alias ${nsp}::${name} ${nsp}::${arg0} {*}${args}
        set_alias ${name} ${args}
    }}
    {*}${aliasCmd} ${nsp} {set_alias} array_setter alias
    {*}${aliasCmd} ${nsp} {alias} {*}${aliasCmd}
        
    # binds nsp argument to current namespace
    alias ${nsp} {nsp_alias} alias ${nsp}

    foreach {name cmd} {

        {get_alias}         {array_getter alias}
        {exists_alias}      {array_exister alias}

        {set_typeof}        {array_setter typeof}
        {get_typeof}        {array_getter typeof}
        {exists_typeof}     {array_exister typeof}

        {set_forward}       {array_setter forward}
        {get_forward}       {array_getter forward}
        {exists_forward}    {array_exister forward}

        {set_dispatcher}    {array_setter dispatcher}
        {get_dispatcher}    {array_getter dispatcher}
        {exists_dispatcher} {array_exister dispatcher}

        {push_fwd}          {stack_push stack_fwd}
        {pop_fwd}           {stack_pop stack_fwd}
        {top_fwd}           {stack_top stack_fwd}
        {with_fwd}          {stack_with stack_fwd}

        {push_mode}         {stack_push stack_mode}
        {pop_mode}          {stack_pop stack_mode}
        {top_mode}          {stack_top stack_mode}
        {with_mode}         {stack_with stack_mode}

        {push_ctx}          {stack_push stack_nest}
        {pop_ctx}           {stack_pop stack_nest}
        {top_ctx}           {stack_top stack_nest}
        {with_ctx}          {stack_with stack_nest}
        
        {push_eval}         {stack_push stack_eval}
        {pop_eval}          {stack_pop stack_eval}
        {top_eval}          {stack_top stack_eval}

    } {
        nsp_alias ${name} {*}${cmd}
    }

    # forward is an alias that pushes its name to stack_fwd
    nsp_alias {forward} {lambda} {name args} {
        {set_forward} ${name} ${args}
        {nsp_alias} ${name} {with_fwd} ${name} {*}${args}
    }

    forward {meta} {lambda} {metaCmd args} {{*}$metaCmd {*}$args}
    forward {keyword} ::dom::createNodeCmd elementNode

    keyword {decl}
    keyword {inst}

    dom createNodeCmd textNode t

    proc nt {text} { t -disableOutputEscaping ${text} }

    nsp_alias {interp_t} interp_if dom_p t

    nsp_alias {interp_execNodeCmd} {lambda} {tag name type args} {
        if { [dom_p] } {
            set cmd [list ::dom::execNodeCmd elementNode ${tag} -x-name ${name} -x-type ${type} {*}${args}]
            uplevel ${cmd}
        } else {
            # TODO: remove -x-attributes from args, one way or another
            if { [llength $args] % 2 == 1 } {
                uplevel [lindex ${args} end]
            } else {
                # do nothing, dom node attributes only in args
            }
            return {::nest::lang::interp_noop}
        }
    }

    nsp_alias {node} {lambda} {tag name type args} \
        {uplevel [list with_eval ${name} interp_execNodeCmd ${tag} ${name} ${type} {*}${args}]}

    # nest argument holds nested calls in the procs below
    proc nest {nest name args} {
        set tag [top_fwd]
        set id [gen_eval_name $name]
        set_typeof ${id} ${tag}

        # TODO: unify to use just one dispatcher for everything
        # forward ${id} [list @ ${id} ${nest}]
        if { [top_mode] eq {decl} } {

            set ::__nest($id) ${nest}

            set ctx [list ${tag} ${id}]
            set nest [list with_ctx ${ctx} {*}${nest}]
            {forward} ${id} {*}${nest}

        }

        # creates dispatcher alias for object/instance methods
        #
        # @${id}
        # => @ ${id}
        # => with_eval ${id}

        {dispatcher} ${id}

        set cmd [list {node} [top_mode] $name $tag -x-id ${id} {*}$args]
        set node [uplevel ${cmd}]

        ###

        if { ![debug_p] } {
            return $node
        }

        set nsp [uplevel {namespace current}]

        if {  $tag ne {base_type} } {

            # $node appendFromScript {
            #     struct.type [$node @x-type] ;# $tag
            #     struct.name [$node @x-name] ;# $name
            #     struct.nsp  [$node @x-nsp]  ;# $nsp
            # }
            ${node} appendFromScript {
                init_slots $node {struct}
            }

            set decls [$node selectNodes {child::decl}]
            foreach decl $decls {
                $decl appendFromScript {
                    # $decl appendFromScript {
                    #     struct.slot.cons          [$decl @x-type]
                    #     struct.slot.name          [$decl @x-name]
                    #     struct.slot.default_value [$decl @x-default_value] (opt) 
                    #     struct.slot.optional_p    [$decl @x-optional_p]    (opt)
                    #     struct.slot.container     [$decl @x-container]     (opt)
                    # }
                    init_slots $decl {struct.slot}
                }
                #$decl setAttribute x-meta {struct.slot}
            }

            #$node setAttribute x-meta ${name}

        }

        return $node

    }

    proc init_slots {node struct} {
        foreach attname [$node attributes] {
            set identifier [string range [set attname] 2 end]
            ${struct}.[set identifier] [$node @[set attname]]
        }
    }


    proc which {name} {

        # check self
        set redirect_name [gen_eval_name ${name}]
        set redirect_exists_p [exists_alias ${redirect_name}] 
        log "checking whether ${name} is $redirect_name (${redirect_exists_p})"
        if { ${redirect_exists_p} } {

            # CASE 1 (self)
            #
            # message msg1 {
            #     ...
            #     fun self(sayhi) {what} { ... }
            #     ...
            # }
            #
            # -> @ msg1 sayhi "world"

            return ${redirect_name}
        }

        # check type/tag of top eval
        if { [exists_typeof [eval_path]] } {
            set eval_ctx_name [eval_path]
            set eval_ctx_tag [get_typeof [eval_path]]
            set redirect_name ${eval_ctx_tag}.${name}
            set redirect_exists_p [exists_alias ${redirect_name}] 
            log "checking in ctx tag (=${eval_ctx_tag}) of top eval (=${eval_ctx_name})... $redirect_name (${redirect_exists_p})"
            if { ${redirect_exists_p} } {

                # CASE 2 (context of top eval)
                #
                # struct message {
                #     varchar subject
                #     ...
                # }
                #
                # message msg1 {
                # --> subject "hello world"
                #     ...
                # }
                #
                # => redirects to message.subject (see log notices below)
                #
                # (case 1) checking whether subject is msg1.subject (0)
                # (case 2) checking in ctx tag (=message) of top eval (=msg1)... message.subject (1)

                return ${redirect_name}
            }
        } else {
            log "did not check top eval (=[eval_path]) - no context info"
        }

        # check nest context
        lassign [top_ctx] ctx_tag ctx_name
        set redirect_name "${ctx_tag}.${name}"
        set redirect_exists_p [exists_alias ${redirect_name}] 
        log "checking in ctx tag (=${ctx_tag}) of parent nest (=${ctx_name})... $redirect_name (${redirect_exists_p})"
        if { [exists_alias ${redirect_name}] } {

            # CASE 3 (context of top nest)
            #
            # struct message {
            #     ...
            #     email from
            #     ...
            # }
            #
            # message msg1 {
            #     ...
            #     from {
            #        name "zena wow"
            #     -> address "zena@example.com"
            #     }
            #     ...
            # }
            #
            # => redirects to email.address (see log notices below)
            #
            # (case 1) checking whether address is msg1.message.from.address (0)
            # (case 2) did not check top eval (=msg1.message.from) - no context info
            # (case 3) checking in ctx tag (=email) of parent nest (=message.from)... email.address (1)

            return ${redirect_name}

        }

        # check for an embedded structure in parent nest, like the one that generic types produce
        set redirect_name ${ctx_name}.${name}
        set redirect_exists_p [exists_alias ${redirect_name}] 
        log "checking in parent nest (=${ctx_name})... $redirect_name (${redirect_exists_p})"
        if { ${redirect_exists_p} } {

            # CASE 4 (unknown types like pair<varchar,varint> embed a dom structure in ctx_name):
            #
            # struct message {
            #     ...
            #     multiple pair<varchar,varint> wordcount
            #     ...
            # }
            #
            # message msg1 {
            #     ...
            #     multiple wordcount {{
            #       first "hello"
            # ----> second "123"
            #     } { ... }}
            #     ...
            # }
            #
            # => redirects to message.wordcount.second (see log notices below)
            #
            # (case 1) checking whether second is msg1.message.wordcount.second (0)
            # (case 2) did not check top eval (=msg1.message.wordcount) - no context info
            # (case 3) checking in ctx tag (=pair) of parent nest (=message.wordcount)... pair.second (0)
            # (case 4) checking in parent nest (=message.wordcount)... message.wordcount.second (1)

            return ${redirect_name}
        }

        return

    }

    proc unknown {arg0 args} {

        set redirect_name [which ${arg0}]

        if { $redirect_name ne {} } {

            log "+++ $arg0 $args -> redirect_name=${redirect_name}"

            if { ![exists_forward ${redirect_name}] } {
                log "redirect (=${redirect_name}) is an alias, i.e. no forward info"
            }

            return [${redirect_name} {*}${args}]  ;# uplevel
        }

        # check for types of the form pair<varchar,varint>
        # forced to do this to keep multiple ignorant of the
        # type it is given

        set last_char [string index ${arg0} end]
        if { $last_char eq {>} } {
            set index [string first {<} ${arg0}]
            set type [string range ${arg0} 0 [expr { ${index} - 1 }]]
            set rest [string range ${arg0} [expr { ${index} + 1 }] end-1]
            set redirect_name [concat ${type} [split ${rest} {,}]]

            # be blind about it
            set node [{*}${redirect_name} {*}${args}]  ;# uplevel
            return $node
        }


        error "no redirect found for [list $arg0] args=[list $args])"


    }

    namespace unknown unknown

    ### HELPERS
 
    proc typedecl {args} {
        
        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        # deal with args and create dom node
        set args [lassign $args arg0]
        if { [lindex $args 0] eq {=} } {
            set args [lreplace $args 0 0 "-x-default_value"]
        }

        set decl_type $tag
        set decl_name $arg0

        set cmd [list with_mode {decl} {node} {decl} $decl_name $decl_type {*}$args]
        set node [{*}${cmd}]  ;# uplevel $cmd

        # get full forward name and register the forward
        set forward_name [gen_eval_name $decl_name]
        set ctx [list $decl_type $decl_name]
        set dotted_nest [list with_mode {inst} $decl_type $forward_name]
        set dotted_nest [list with_ctx $ctx {*}$dotted_nest] 
        {forward} $forward_name {*}$dotted_nest

        log "(declaration done) decl_type=$decl_type decl_name=$decl_name forward_name=$forward_name"

        return $node

    }

    proc typeinst {args} {
        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        # message.subject "hello" 
        # => inst_name=message.subject args={{hello}} 
        # => inst_name=message.subject inst_type=base_type
        
        set inst_type $tag
        set args [lassign $args inst_name inst_arg0]
        if { $args ne {} } { 
            error "something wrong with instantiation statement args=[list $args]"
        }
        set inst_arg0 [list ::nest::lang::interp_t $inst_arg0]
        set cmd [list with_mode {inst} {node} {inst} ${inst_name} ${inst_type} ${inst_arg0}]
        return [uplevel ${cmd}]
    }

    # case for composite or "unknown" types (e.g. pair<varchar,varint)
    proc {objectinst} {args} {
        set tag [top_fwd]
        lassign [top_ctx] ctx_tag ctx_name
        set inst_type $ctx_tag
        set inst_name $tag   ;# for inst_type=struct.slot => tag=struct.name => arg0=name
        set cmd [list with_mode {inst} {node} {inst} ${inst_name} ${inst_type} {*}$args]
        return [uplevel ${cmd}]
    }


    nsp_alias {objectdecl} {typedecl}
    # nsp_route {type} eval top_mode
    # nsp_route {object} eval top_mode
    proc {type_helper} {args} {::nest::lang::type[top_mode] {*}${args}}
    proc {object_helper} {args} {::nest::lang::object[top_mode] {*}${args}}



    # qualifier_helper
    #
    # DECLARATION EXAMPLE 1 ( llength_args==1 && arg0 ne {struct} ):
    #   struct message {
    #     ...
    #     multiple word_count_pair wordcount
    #     ...
    #   }
    #
    # DECLARATION EXAMPLE 2 ( llength_args==2 && arg0 eq {struct} ):
    #   struct message {
    #     ...
    #     multiple struct wordcount { 
    #       varchar word
    #       varint count
    #     }
    #     ...
    #   }
    #
    #
    # DECLARATION EXAMPLE 3 ( llength_args==3 && arg0 ne {struct} ):
    #   struct message {
    #     ...
    #     multiple word_count_pair wordcount = {}
    #     ...
    #   }
    #
    # DECLARATION EXAMPLE 4 ( llength_args==4 && arg0 eq {struct} ):
    #   struct message {
    #     ...
    #     multiple struct wordcount = {} { 
    #       varchar word
    #       varint count
    #     }
    #     ...
    #   }
    #


    proc qualifierdecl {attname attvalue arg0 args} {
        set args [lassign $args name]
        if { [lindex $args 0] eq {=} } {
            set args [lreplace $args 0 0 "-x-default_value"]
        }

        set node [$arg0 $name {*}$args]
        ${node} setAttribute x-$attname $attvalue
        return ${node}
    }

    proc qualifierinst {attname attvalue args} {
        set node [uplevel $args]
        ${node} setAttribute x-$attname $attvalue
        return ${node}
    }

    proc {qualifier_helper} {args} {::nest::lang::qualifier[top_mode] {*}${args}}


    # Containers
    #
    # INSTANTIATION EXAMPLE 1:
    # 
    #   multiple wordcount {{ 
    #       word "the"
    #       count "123"
    #   } {
    #   } { 
    #       word "and" 
    #       count "54" 
    #   }}
    #
    #

    proc {containerinst} {attname attvalue arg0 args} {
        set args [lassign $args argvals]
        set arg0 [which $arg0]

        set nodes [list]
        foreach argval $argvals {
            set node [uplevel \
                [list {qualifierinst} ${attname} ${attvalue} ${arg0} ${argval}]]
            lappend nodes ${node}
        }
        return ${nodes}
    }

    nsp_alias {containerdecl} {qualifierdecl}

    proc {container_helper} {args} {::nest::lang::container[top_mode] {*}${args}}

    ### THE LANGUAGE

    ## basis of class/object methods

    nsp_alias {@} with_eval

    nsp_alias {dispatcher} {lambda} {id} {
        set_dispatcher ${id} "@${id}"
        nsp_alias "@${id}" {@} ${id}
    }

    ## class/object aliases, used in def of base_type and struct
    nsp_alias object nest {object_helper}
    nsp_alias class with_mode {decl} {nest}

    ## qualifiers
    forward {multiple} container_helper container multiple
    forward {optional} qualifier_helper optional_p true
    forward {required} qualifier_helper optional_p false

    ## data types
    meta {class} {class {type_helper}} base_type

    # a varying-length text string encoded using UTF-8 encoding
    base_type "varchar"

    # a boolean value (true or false)
    base_type "bool"

    # a varying-bit signed integer
    base_type "varint"

    # an 8-bit signed integer
    base_type "byte"

    # a 16-bit signed integer
    base_type "int16"

    # a 32-bit signed integer
    base_type "int32"

    # a 64-bit signed integer
    base_type "int64"

    # a 64-bit floating point number
    base_type "double"

    # timestamp/date
    base_type "date"


    ## Generic Types

    forward {generic_type} {lambda} {forward_name params body nest} {
        forward ${forward_name} {lambda} \
            [lappend {params} {name}] \
                [concat {nest} [list ${nest}] "\${name}" [list ${body}]]
    }

    # pair construct, equivalent to:
    #
    # => forward {pair} {lambda {typefirst typesecond name} {
    #        nest {type_helper} ${name} {
    #            ${typefirst} {first} 
    #            ${typesecond} {second}
    #        }
    #    }}

    generic_type {pair} {typefirst typesecond} {
        ${typefirst} {first}
        ${typesecond} {second}
    } {object_helper}



    ## Metaclass struct

    meta {class} {class {object}} {struct} {
        varchar id
        varchar name
        varchar type
        varchar nsp
        varchar default_value = ""

        multiple struct slot = {} {
            varchar id
            varchar name
            varchar type
            varchar default_value = ""
            bool optional_p = false
            varchar container = ""
        }

        varchar pk
        bool is_final_if_no_scope

    }

    ## self procs

    struct {fun} {
        varchar name
        multiple varchar param = {}
        varchar body
    }

    proc gen_shadow_name {name} { return _${name} }

    nsp_alias {shadow_alias} {lambda} {name args} {
        rename ${name} [gen_shadow_name ${name}]
        set cmd [list nsp_alias ${name} {*}${args}]
        uplevel ${cmd}
    }

    nsp_alias {shadow} {lambda} {name args} {
        set cmd [list [gen_shadow_name ${name}] {*}${args}]
        uplevel ${cmd}
    }

    shadow_alias {fun} {lambda} {fun_name fun_params fun_body} {

        nsp_alias [gen_eval_name ${fun_name}] {lambda} ${fun_params} ${fun_body}

        # must be last so that it returns the dom node
        # otherwise, we would have to keep the resulting 
        # node in a variable and return it at the end

        with_mode {inst} shadow fun ${fun_name} {
            name ${fun_name}
            multiple param ${fun_params}
            body ${fun_body}
        }

    }

    namespace export "struct" "varchar" "bool" "varint" "byte" "int16" "int32" "int64" "double" "multiple"

} lang_doc

if { [::nest::debug::dom_p] } {
    puts [$lang_doc asXML]
}


define_lang ::nest::data {

    upvar ::nest::lang::dispatcher {}

    namespace import ::nest::lang::*
    namespace path [list ::nest::data ::nest::lang]
    namespace unknown ::nest::lang::unknown

}




