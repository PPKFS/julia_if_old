module InteractiveFiction

using Printf, Parameters, Random, Pipe, DataStructures

include("types.jl")

export ObjectGraphNode, ObjectGraph, World, DynamicString, Text, Object, Optional
export @do_while, @register_attribute

function toggle_dbg!()
    global dbg_on
    dbg_on = !dbg_on
end
export toggle_dbg!

function Activity(name::Symbol, main::Function)
    a = Activity(name, create_blank_rulebook(:before), create_blank_rulebook(:carry_out), create_blank_rulebook(:after))
    add_rule!(a.carry_out_rules, :activity, main)
    a
end

function Activity(name::Symbol, before::Rulebook, carry::Rulebook, after::Rulebook)
    a = Activity(name, before, carry, after, Dict())
end

function Activity(name::Symbol, main::Function, before::Rulebook, after::Rulebook)
    a = Activity(name, before, create_blank_rulebook(:carry_out), after, Dict())
    add_rule!(a.carry_out_rules, :activity, main)
    a
end

function create_blank_rulebook(n::Symbol)
    Rulebook(n, nothing, [], [], [], Dict())
end

function create_blank_action(n::Symbol)::Action
    nstr = string(n)
    Action(n, [nstr], 1, create_blank_rulebook(:set_action_variables), create_blank_rulebook(:before_rules),
    create_blank_rulebook(:check_rules), create_blank_rulebook(:carry_out_rules),
    create_blank_rulebook(:report_rules), Dict())
end

const name(w::World, s::Symbol) = name(w.objects[s])
const name(o::Object)::String = o.name
const name(r::Rulebook)::String = string(r.name)
const name(r::Rule)::String = string(r.name)
const name(a::Action)::String = string(a.name)
const player(w::World)::Object = w.player
const type(o::Object)::Symbol = o.type

function get_object(w::World, o::Symbol)
    return w.objects[o]
end

function istype(o::Object, t::Symbol)
    w = o.world
    st = [type(o)]
    while length(st) > 0
        s = pop!(st)
        if s == t
            return true
        end
        map(y -> push!(st, y.type), w.object_hierarchy[s].parents)
    end
    return false
end

Base.isequal(o::Object, s::Symbol) = id(o) == s
Base.isequal(s::Symbol, o::Object) = id(o) == s
#
function istype(w::World, o::Symbol, t::Symbol)
    istype(w, w.objects[o], t)
end

function hasattr(o::Object, s::Symbol)
    haskey(o.attrs, s)
end

export name

const id(o::Object)::Symbol= o.id
export id

function make_blank_world(title::String)::World
    w = World(title = title, first_room=nothing, player=nothing)
    make_type!(w, :object, Vector{Symbol}(), make_object_type!)
    make_type!(w, :direction, :object, make_direction_type!)
    make_type!(w, :thing, :object, make_thing_type!)
    make_type!(w, :room, :object, make_room_type!)
    add_base_rulebooks!(w)
    create_directions!(w)
    add_base_actions!(w)
    add_base_activities!(w)
    player = add_thing!(w, "yourself"; id=:player, description = "As good-looking as ever")
    add_object!(w, :room, "Nowhere Room"; id=NOWHERE_ROOM, description = "The void. If you see this, you messed up.")
    w.first_room = w.objects[NOWHERE_ROOM]
    w.player = w.objects[player]
    location(w.player, w.first_room)
    w
end
export make_blank_world

function Base.show(io::IO, o::Object)
    print(io, @sprintf "%s (ID: %s, Type: %s)" o.name o.id string(o.type))
end

function Base.show(io::IO, ::MIME"text/plain", o::Object)
    print(io, @sprintf "%s (ID: %s, Type: %s)\n\nProperties:\n%s\n" o.name o.id string(o.type) join([string(k, " - ", v) for (k, v) in filter(x -> !(x[2] isa AliasOf) ,o.attrs)], "\n"))
end

function Base.show(io::IO, a::Action)
    print(io, a.name)
end

function indent!(w::World)
    w.message_indent += 1
end

function unindent!(w::World)
    w.message_indent -= 1
end

function indent_dbg!(w::World)
    w.message_indent += 1
end

function unindent_dbg!(w::World)
    w.message_indent -= 1
end
export indent!
export unindent!

buf = []

isnewline = true

function sayln!(w::World, str::Text, args...; kwargs...)
    w.print_counter +=1
    #print(repeat('\t', getindex(w.message_indent)))
    #printstyled(string(getindex(w.print_counter), " "); color = :yellow)
    println(str, args...; kwargs...)
    global buf
    global isnewline
    if isnewline
        push!(buf, str)
    else
        buf[end] = string(buf[end], str)
    end
    isnewline = true
    nothing
end

function say!(w::World, str::Text, args...; kwargs...)
    w.print_counter +=1
    #print(repeat('\t', getindex(w.message_indent)))
    #printstyled(string(getindex(w.print_counter), " "); color = :yellow)
    print(str, args...; kwargs...)
    global buf
    global isnewline
    if isnewline
        push!(buf, str)
    else
        buf[end] = string(buf[end], str)
    end
    isnewline = false
    nothing
end
export say!
export sayln!

dbg_on = false
function say_dbg!(w::World, str::Text, args...; kwargs...)
    if !dbg_on
        return
    end
    w.print_counter +=1
    print(repeat('\t', w.message_indent))
    printstyled(getindex(w.print_counter); color = :yellow)
    printstyled("MSG: "; color = :blue)
    print(str, args...; kwargs...)
end
export say_dbg!

function say_dbgln!(w::World, str::Text, args...; kwargs...)
    if !dbg_on
        return
    end
    w.print_counter +=1
    print(repeat('\t', getindex(w.message_indent)))
    printstyled(getindex(w.print_counter); color = :yellow)
    printstyled("MSG: "; color = :blue)
    println(str, args...; kwargs...)
end
export say_dbgln!

function err_dbg!(w::World, str::Text, args...; kwargs...)
    if !dbg_on
        return
    end
    w.print_counter +=1
    print(repeat('\t', getindex(w.message_indent)))
    printstyled(getindex(w.print_counter); color = :yellow)
    printstyled("ERR: "; color = :red)
    println(str, args...; kwargs...)
end
export err_dbg!

function make_object(w::World, t::Symbol, name::String, id=nothing)::Object
    iters = 0
    obj = Object(t, name, isnothing(id) ? Symbol(randstring(8)) : id, Dict(), w)
    stack = [w.object_hierarchy[t]]
    rev_stack = []
    @do_while length(stack) > 0 begin
        #update the type here
        iters += 1 #just a sanity check for loops
        current_type = popfirst!(stack)
        #current_type.build!(obj)
        push!(stack, current_type.parents...)
        push!(rev_stack, current_type)
        if iters > 1000 
            println("LIKELY CYCLIC GRAPH PROBLEM") 
        end
    end
    @do_while length(rev_stack) > 0 begin
        iters += 1 #just a sanity check for loops
        build_object!(w, obj, pop!(rev_stack))
        if iters > 1000
            println("LIKELY CYCLIC GRAPH PROBLEM") 
        end
    end
    obj
end
export make_object

function build_object!(w::World, obj::Object, t::ObjectGraphNode)
    for x in t.attributes
        ops = w.attribute_store[x][t.type]
        #TODO: remember what this even is checking for
        if length(ops) == 3
            set_attr!(obj, x, ops[1])
        else
            set_attr!(obj, x, ops[2])
        end
        if ops[1] isa Vector
             #iterate each option and add an AliasOf
            if length(ops[1]) > 2
                println("cannot handle 3-option things rn")
            end
            set_attr!(obj, ops[1][1], AliasOf(x, ops[1][2]))
            set_attr!(obj, ops[1][2], AliasOf(x, ops[1][1]))
        end
    end
end
function make_type!(world::World,name::Symbol, parent::Symbol, build::Function)
    make_type!(world, name, [parent], build)
end

function make_type!(world::World, name::Symbol, parents::Vector{Symbol}, build!::Function)
    world.object_hierarchy[name] = ObjectGraphNode(name, [], 
        map(x -> world.object_hierarchy[x], parents), Set())
    build!(world)
    for x in parents
        push!(world.object_hierarchy[x].children, world.object_hierarchy[name])
    end
end
export make_type!

function can_be!(t::Symbol, w::World, attr_name::Symbol, options::Symbol; usually=nothing::Optional{String})
    can_be!(t, w, attr_name, [options, Symbol(string("not_", string(options)))]; usually=usually)
end

function can_be!(t::Symbol, w::World, attr_name::Symbol, options::Vector; usually=nothing::Optional{Any},
    never=nothing::Optional{Any})
    if !haskey(w.attribute_store, attr_name)
        w.attribute_store[attr_name] = Dict{Symbol, Any}()
    end
    if !haskey(w.attribute_store, t)
        w.attribute_store[t] = Set()
    end
    is_dynamic = usually isa Function
    w.attribute_store[attr_name][t] = (options,
        isnothing(usually) ? options[1] : usually, never, is_dynamic)
    push!(w.object_hierarchy[t].attributes, attr_name)
    map(y -> push!(w.attribute_store[t], (y, attr_name)), options)
end
export can_be!

function has!(t::Symbol, w::World, attr_name::Symbol; usually=nothing, never=nothing)
    if !haskey(w.attribute_store, attr_name)
        w.attribute_store[attr_name] = Dict{Symbol, Any}()
    end
    if !haskey(w.attribute_store, t)
        w.attribute_store[t] = Set()
    end
    push!(w.object_hierarchy[t].attributes, attr_name)
    is_dynamic = usually isa Function
    w.attribute_store[attr_name][t] = (isnothing(usually) ? "" : usually, never, is_dynamic)
    push!(w.attribute_store[t], attr_name)
end
export has!

const NOTHING_ID = :NA
const NOWHERE_ROOM = :NOWHERE_ROOM

function get_attr(w::World, o::Symbol, a::Symbol)
    get_attr(w.objects[o], a)
end

function get_attr(o::Object, a::Symbol)
    if o.id == NOTHING_ID
        throw(ErrorException("can't do stuff with the nothing object"))
    end
    attr = o.attrs[a]
    #if it's dynamic, then we have a function we need to call instead.
    if attr[2]
        return attr[1](o)
    else
        return attr isa AliasOf ? get_attr(o, attr.attr) == a : attr[1]
    end
end
function make_object_type!(w::World)
    t = :object
    can_be!(t, w, :name_plurality, [:single_named, :plural_named]; usually=:single_named)
    can_be!(t, w, :proper_named, [:proper_named, :improper_named]; usually = :improper_named)
    has!(t, w, :indefinite_article; usually="the")
    has!(t, w, :understand_as)
end

function make_direction_type!(w::World)
    t = :direction
    has!(t, w, :opposite)
end

function make_room_type!(w::World)
    t = :room
    can_be!(t, w, :lighted_attr, [:lighted, :dark]; usually = :lighted)
    can_be!(t, w, :visited_attr, :visited; usually = :not_visited)
    has!(t, w, :located_at; usually=Set())
    has!(t, w, :description)
    has!(t, w, :map_connections; usually=Dict())
end

function make_thing_type!(w::World)
    thing = :thing
    can_be!(thing, w, :lit_attr, [:lit, :unlit]; usually = :unlit)
    can_be!(thing, w, :edible_attr, [:edible, :inedible]; usually = :inedible)
    can_be!(thing, w, :portable_attr, [:fixed_in_place, :portable]; usually = :portable)
    can_be!(thing, w, :wearable_attr, :wearable; usually = :not_wearable)
    has!(thing, w, :description; usually = "")
    has!(thing, w, :location; usually = NOWHERE_ROOM)
    can_be!(thing, w, :pushable_between, :pushable_between_rooms; usually = :pushable_between_rooms)
    can_be!(thing, w, :handled_attr, :handled)
    can_be!(thing, w, :described_attr, :described; usually = :described)
    can_be!(thing, w, :mentioned_attr, :mentioned; usually = :mentioned)
    can_be!(thing, w, :listing_marked, :marked_for_listing; usually = :not_marked_for_listing)
    has!(thing, w, :initial_appearance; usually = "")
end

function set_attr!(w::World, id::Symbol, name::Symbol, val::Any)
    set_attr!(w.objects[id], name, val)
end

function set_attr!(o::Object, name::Symbol, val::Any)
    if haskey(o.attrs, name) && o.attrs[name] isa AliasOf
        set_attr!(o, o.attrs[name].attr, val ? name : o.attrs[name].other)
    else
        o.attrs[name] = (val, val isa Function)
    end
end
export set_attr!

function add_object!(w::World, t::Symbol, n::String, args...; kwargs...)::Symbol
    obj = make_object(w, t, n, haskey(kwargs, :id) ? kwargs[:id] : nothing)
    for (k, v) in kwargs
        set_attr!(obj, k, v)
    end
    for k in args
        set_attr!(obj, k, true)
    end
    w.objects[obj.id] = obj
    if !haskey(w.objects_by_type, t)
        w.objects_by_type[t] = []
    end
    push!(w.objects_by_type[t],obj)
    return obj.id
end
export add_object!

function add_object!(w::World, o::Object)
    w.objects[id(o)] = o
    t = type(o)
    if !haskey(w.objects_by_type, t)
        w.objects_by_type[t] = []
    end
    push!(w.objects_by_type[t], o)
end

function add_thing!(w::World, n::String, args...; kwargs...)::Symbol
    add_object!(w, :thing, n, args...; kwargs...)
end
export add_thing!

function add_room!(w::World, n::String, args...; kwargs...)::Symbol
    s = add_object!(w, :room, n, args...; kwargs...)
    if id(w.first_room) == NOWHERE_ROOM
        w.first_room = w.objects[s]
    end
    s
end
export add_room!

function add_rulebook!(w::World, name::Symbol)::Rulebook
    w.rulebooks[name] = create_blank_rulebook(name)
    w.rulebooks[name]
end

function run(f, w::World)
    global buf
    for x in buf
        println(x)
    end
    buf = []
    w.message_indent = 0
    isnewline = true
    nothing
end

function follow_ruleset!(w::World, ruleset::Vector{Rule}, rb::Rulebook, args...)
    res = nothing
    for rule in ruleset
        say_dbgln!(w, @sprintf "Following the %s" name(rule))
        if haskey(rb.variables, :actor) && id(rb.variables[:actor]) != :player && !rule.any_actor
            println(rb.variables, rule.any_actor)
            continue
        end
        res = rule.rule(w, rb, args...)
        if res != nothing
            break
        end
    end
    res
end

function follow_rulebook!(world::World, rulebook::String, args...)
    follow_rulebook!(world, world.rulebooks[rulebook], args...)
end

function follow_rulebook!(w::World, rulebook::Rulebook, args...)
    say_dbgln!(w, @sprintf "Following the %s rulebook" name(rulebook))
    indent_dbg!(w)
    res = follow_ruleset!(w, rulebook.first_rules, rulebook, args...)
    if res == nothing
        res = follow_ruleset!(w, rulebook.rules, rulebook, args...)
        if res == nothing
            res = follow_ruleset!(w, rulebook.last_rules, rulebook, args...)
        end
    end
    unindent_dbg!(w)
    say_dbgln!(w, @sprintf("Finished following the %s rulebook with resolution: %s", 
        name(rulebook), res == nothing ? "no outcome" : res))
    res
end
export follow_rulebook!

function do_activity!(w::World, n::Symbol, args...)
    act = w.activities[n]
    follow_rulebook!(w, act.before_rules, act, args...)
    follow_rulebook!(w, act.carry_out_rules, act, args...) #todo: make this "just the one most specific"
    follow_rulebook!(w, act.after_rules, act, args...)
end

function print_name!(w::World, n::Symbol, args...)
    do_activity!(w::World, :printing_name, n, args...)
end

const default_rule(w::World)::Nothing = nothing

const rulenotimpl(s::Symbol)::Function = (w, rb) -> err_dbg!(w, string("rule not implemented: ", string(s)))

export default_rule

function add_rule!(rulebook::Rulebook, name::Symbol, any_actor=true::Bool)
    add_rule!(rulebook, name, default_rule, any_actor)
end

function add_rule!(world::World, rulebook::Symbol, name::Symbol, rule::Function, any_actor=true::Bool)
    add_rule!(world.rulebooks[rulebook], name, rule, any_actor)
end

function add_rule!(rulebook::Rulebook, name::Symbol, rule::Function, any_actor=true::Bool)
    push!(rulebook.rules, Rule(name, rule, any_actor))
end
export add_rule!

function add_rule_first!(rulebook::Rulebook, name::Symbol, rule::Function, any_actor=true::Bool)
    push!(rulebook.first_rules, Rule(name, rule, any_actor))
end
export add_rule_first!

function add_rule_last!(rulebook::Rulebook, name::Symbol, any_actor=true::Bool)
    add_rule_last!(rulebook, name, default_rule, any_actor)
end

function add_rule_last!(rulebook::Rulebook, name::Symbol, rule::Function, any_actor=true::Bool)
    push!(rulebook.last_rules, Rule(name, rule, any_actor))
end
export add_rule_last!

function add_activity!(w::World, n::Symbol, main_rule::Function)
    w.activities[n] = Activity(n, main_rule)
end

function add_activity!(w::World, n::Symbol, before::Rulebook, carry::Rulebook, after::Rulebook)
    w.activities[n] = Activity(n, before, carry, after)
end

function default_rule(world) end

function when_play_begins!(world::World, rule_name::Symbol, rule = default_rule::Function, any_actor=true::Bool)
    add_rule!(world, :when_play_begins, rule_name, rule)
end
export when_play_begins!

function direction!(w::World, n::String, short::Symbol)::Symbol
    add_object!(w, :direction, n, short; understand_as=[string(short)])
end
export direction!

function room!(w::World, name::String, args...; kwargs...)
    if !(:description in keys(kwargs))
        kwargs = (kwargs..., description = @sprintf "It's the %s." name)
    end
    obj = add_object!(w, name, :room, args...; kwargs...)
    if w.first_room.id == "0xNOWHERE_ROOM"
        w.first_room = obj
    end
    obj
end
export room!

function move!(world::World, obj::Object, new_loc::Symbol)
    move!(world, obj, world.rooms[new_loc])
end

function move!(world::World, obj::Object, new_loc::Object)
    say_dbgln!(world, @sprintf "moved %s from %s to %s" name(obj) location(obj) name(new_loc))
    location(obj, id(new_loc))
end

function add_base_rulebooks!(w::World)
    
    function set_action_vars(world::World, r::Rulebook)
        action = r.variables[:action]
        action.action_variables[:actor] = r.variables[:actor]
        action.action_variables[:nouns] = r.variables[:nouns]
        follow_rulebook!(world, action.set_action_variables, action)
        for (k, v) in action.action_variables
            action.before_rules.variables[k] = v
            action.carry_out_rules.variables[k] = v
            action.report_rules.variables[k] = v
        end
    end

    function intro_text(world::World, rb::Rulebook)
        tot_len = length("-------") + length(world.title) + length("-------")
        say!(world, repeat("-", tot_len))
        say!(world, "\n")
        say!(world, "-------")
        say!(world, world.title)
        say!(world, "-------\n")
        say!(world, repeat("-", tot_len))
        say!(world, "\n\n\n")
    end

    #=
    def descend_processing(world, actor, action, nouns):
        return world.rulebooks["specific action processing rules"].follow(actor=actor, action=action, nouns=nobineuns)

    def work_out_details(world, actor, action, nouns):
        pass
    =#
    function position_player(world::World, r::Rulebook)::Nothing
        move!(world, world.player, world.first_room)
        nothing
    end

    function check_rules(world::World, r::Rulebook)
        #get the previous rulebook to get the variables there.
        ap = world.rulebooks[:action_processing]
        return follow_rulebook!(world, ap.variables[:action].check_rules)
    end

    function carry_out_rules(world::World, r::Rulebook)
        #get the previous rulebook to get the variables there.
        ap = world.rulebooks[:action_processing]
        return follow_rulebook!(world, ap.variables[:action].carry_out_rules)
    end

    function clean_actions(w::World, r::Rulebook)
        for k in keys(r.variables[:action].action_variables)
            delete!(r.variables[:action].action_variables, k)
        end
        for k in keys(r.variables)
            delete!(r.variables, k)
        end
    end
    begins = add_rulebook!(w, :when_play_begins)
    add_rule_first!(begins, :display_banner, intro_text)
    add_rule_first!(begins, :position_player_in_world, position_player)
    add_rule_first!(begins, :initial_room_description, (x, rb) -> begin try_action!(x, "looking"); nothing end)

    add_rulebook!(w, :before)
    add_rulebook!(w, :instead)

    ap = add_rulebook!(w, :action_processing)
    #announce multiple from list, set pronouns are skipped
    #what????
    add_rule_first!(ap, :set_action_variables, set_action_vars)
    add_rule_first!(ap, :before_stage, (x, rb) -> follow_rulebook!(x, x.rulebooks[:before]))
    add_rule!(ap, :carrying_requirements, rulenotimpl(:carrying_requirements))
    add_rule!(ap, :basic_visibility, rulenotimpl(:basic_visibility))
    add_rule!(ap, :basic_accessibility, rulenotimpl(:basic_accessibility))
    add_rule!(ap, :instead_stage, (x, rb) -> follow_rulebook!(x, x.rulebooks[:instead]))
    add_rule!(ap, :requested_actions_require_persuasion, rulenotimpl(:requested_actions_require_persuasion)) 
    add_rule!(ap, :carry_out_requested_actions, rulenotimpl(:carry_out_requested_actions))
    add_rule!(ap, :investigate_player_awareness, rulenotimpl(:investigate_player_awareness))
    add_rule!(ap, :check_stage, check_rules)
    add_rule!(ap, :carry_out_stage, carry_out_rules)
    add_rule!(ap, :after_stage, rulenotimpl(:after_stage))
    add_rule!(ap, :investigate_player_awareness_after, rulenotimpl(:investigate_player_awareness_after))
    #add_rule(sap, "report stage rule", lambda world, actor, action, nouns: action.report_rules.follow(action=action))
    add_rule_last!(ap, :clean_actions, clean_actions)
    add_rule_last!(ap, :end_action_processing, (x, rb) -> true)
end

function things_located_at(w::World, o::Object; include_indirect=false)
    things = []
    for x in located_at(o)
        push!(things, x)
    end
    things
end

function add_base_activities!(w::World)
    function printing_dark_room(w::World, rb::Rulebook)
        say!(w, "Darkness")
    end

    function printing_desc_dark_room(w::World, rb::Rulebook, ac)
        sayln!(w, "It is pitch dark, and you can't see a thing.")
    end

    function printing_name(w::World, rb::Rulebook, ac, n::Union{Symbol, Object})
        if n isa Symbol
            n = w.objects[n]
        end
        say!(w, name(n))
    end

    function describing_locale(w::World, rb::Rulebook, a::Activity, o::Object)
        pq = a.activity_variables[:locale_priorities]
        for (item, _) in pq
            do_activity!(w, :print_locale_paragraph_about, item)
        end
    end

    function also_see_locale(w::World, rb::Rulebook, a::Activity, o::Object)
        #rb.variables[:mentionable_count] = 0
        also_see = []
        pq = a.activity_variables[:locale_priorities]
        for (item, priority) in pq
            if priority < 0
                marked_for_listing!(w, item, a.activity_variables[:])
                push!(also_see, item)
            end
        end
        if length(also_see) > 0
            if istype(w, o, :supporter) || istype(w, o, :animal)
                say!(w, "On {the :supporter} you ", :supporter => o)
            elseif istype(w, o, :room) && id(o) == location(player)
                    say!(w, "You ")
            else
                say!(w, "In {the :obj} you ", :obj => o)
            end
            say!("can {if :pgraph_count}also {endif}see ", :pgraph_count => rb[:locale_paragraph_count] > 0)
        end
        common_holder = nothing
        contents_form_of_list = true
        for x in also_see
            if common_holder != held_by(x)
                if isnothing(common_holder)
                    common_holder = held_by(x)
                else
                    contents_form_of_list = false
                end
            end
        end
        if contents_form_of_list && !isnothing(common_holder)
            #list the contents of the common holder, as a sentence, including contents, 
            #giving brief inventory information, tersely, not listing concealed items, 
            #listing marked items only;
            sayln!(w, "print the list of things")
        else
            sayln!(w, "everything else here.")
        end
        if o == location(w.player)
            say!(w, " here")
        end
        sayln!(w, ".")
    end

    #TODO: need to feed activities the corresponding activity not the rulebook

    function init_locale(w::World, rb::Rulebook, a::Activity, o::Object)
        a.activity_variables[:locale_priorities] = PriorityQueue()
        a.activity_variables[:locale_paragraph_count] = 0
        if haskey(a.activity_variables, :mentionable_timestamp)
            a.activity_variables[:mention_timestamp] += 1
        else
            a.activity_variables[:mention_timestamp] = 1
        end
        for obj in things_located_at(w, o)
            a.activity_variables[:locale_priorities][id(obj)] = -5
        end
    end

    #function find_interesting_stuff(w::World, rb::Rulebook, o::Object)

    before_locale = create_blank_rulebook(:before_printing_locale)
    after_locale = create_blank_rulebook(:after_printing_locale)
    carry_out_locale = create_blank_rulebook(:carry_out_locale)

    add_rule_first!(before_locale, :initialise_locale, init_locale)
    add_rule!(carry_out_locale, :interesting_locale_paragraphs, describing_locale)
    add_rule!(carry_out_locale, :you_can_also_see, also_see_locale)

    add_activity!(w, :printing_name_of_a_dark_room, printing_dark_room)
    add_activity!(w, :printing_description_of_a_dark_room, printing_desc_dark_room)
    add_activity!(w, :printing_name, printing_name)
    add_activity!(w, :describing_locale,  before_locale, carry_out_locale,after_locale)
end
function add_base_actions!(w::World)
    create_looking!(w)
end

function create_directions!(world::World)
    n = direction!(world, "north", :n)
    ne = direction!(world, "northeast", :ne)
    nw = direction!(world, "northwest", :nw)
    s = direction!(world, "south", :s)
    se = direction!(world, "southeast", :se)
    sw = direction!(world, "southwest", :sw)
    e = direction!(world, "east", :e)
    w = direction!(world, "west", :w)
    u = direction!(world, "up", :u)
    d = direction!(world, "down", :d)
    i = direction!(world, "inside", :in)
    o = direction!(world, "outside", :out)
    opposite(world, n, s)
    opposite(world, n, s)
    opposite(world, s, n)
    opposite(world, ne, sw)
    opposite(world, nw, se)
    opposite(world, se, nw)
    opposite(world, sw, ne)
    opposite(world, e, w)
    opposite(world, w, e)
    opposite(world, i, o)
    opposite(world, o, i)
end

function run_world!(world::World)
    global buf
    global isnewline
    world.message_indent = 0
    buf = []
    isnewline = true
    follow_rulebook!(world, world.rulebooks[:when_play_begins])
    s = join(buf, "\n")
    println("----------")
    buf = []
    if dbg_on
        println(s)
    end
    isnewline = true
    s
end
export run_world!

function try_action!(w::World, a::Symbol)
    try_action!(w, w.actions[a], [], player(w))
end

function try_action!(w::World, a::String)
    try_action!(w, w.actions[Symbol(a)], [], player(w))
end

function try_action!(w::World, a::Action)
    try_action!(w, a, [], player(w))
end

function try_action!(world::World, action::Action, nouns::Vector)
    try_action!(world, action, nouns, player(world))
end

function try_action!(world::World, action::Action, nouns::Vector, actor::Object)
    n = (name(actor) == "yourself" ? "the player" : name(actor))
    say_dbgln!(world, @sprintf "%s is trying to do %s" n action.name)
    indent_dbg!(world)
    ap = world.rulebooks[:action_processing]
    ap.variables[:actor] = actor
    ap.variables[:action] = action
    ap.variables[:nouns] = nouns
    outcome = follow_rulebook!(world, ap)
    unindent_dbg!(world)
    if outcome != nothing
        say_dbgln!(world, @sprintf "outcome of %s trying to do %s is %s" n action outcome)
    end
    say_dbgln!(world, @sprintf "%s has finished trying to perform the action %s" n action)
    return outcome
end
export try_action!

const actor(r::Rulebook) = r.variables[:actor]
function create_looking!(w::World)
    look = create_blank_action(:looking)
    look.understand_as = ["look"]
    look.applies_to = 0
    w.actions[:looking] = look

    function find_visibility_holder(w::World, s::Symbol)
        find_visibility_holder(w, w.objects[s])
    end

    function find_visibility_holder(w::World, o::Object)
        if hasattr(o, :supported_by)
            return supported_by(o)
        elseif hasattr(o, :enclosed_by)
            return enclosed_by(o)
        else #TODO: add in opaque objects
            return location(o)
        end
    end
    #abbbrv form allowed is "are we using go"
    function desc_heading_rule(w::World, r::Rulebook)
        #we can safely asssume if we are here, the actor is the player.
        if r.variables[:visibility_level] == 0
            do_activity!(w, :printing_name_of_a_dark_room)
        elseif r.variables[:visibility_ceiling] == location(w.player)
            print_name!(w, location(w.player))
        else
            print_name!(w, r.variables[:visibility_ceiling])
            sayln!()
        end
        imd_lvl = find_visibility_holder(w, actor(r))
        for i = 2:r.variables[:visibility_level]
            if istype(w, imd_lvl, :supporter)
                say!(w, "(on ")
            else
                say!(w, "(in ")
            end
            print_name!(w, imd_lvl)
            say!(w, ")")
            imd_lvl = find_visibility_holder(w, imd_lvl)
        end
        sayln!(w, "\n") #TODO: "run paragraph on with special look spacing"?
    end

    function desc_body_rule(world::World, r::Rulebook)
        if r.variables[:visibility_level] == 0
            if world.room_descriptions == :abbreviated ||
                (world.room_descriptions == :sometimes_abbreviated && world.darkness_witnessed)
                return
            end
            do_activity!(w, :printing_description_of_a_dark_room)
        elseif r.variables[:visibility_ceiling] == location(world.player)
            if world.room_descriptions == :abbreviated ||
                (world.room_descriptions == :sometimes_abbreviated && r.variables[:room_describing_action] != :looking)
                return
            end
            say!(world, @pipe world.player |> location |> description(world, _))
        end
    end

    #I have 0 clue what this code does but it's what the spec says.
    function desc_obj_rule(world::World, r::Rulebook)
        if r.variables[:visibility_level] == 0
            return
        end
        imd_lvl = actor(r)
        ip_cnt = r.variables[:visibility_level]
        while ip_cnt > 0
            marked_for_listing(imd_lvl, true)
            imd_lvl = find_visibility_holder(w, imd_lvl)
            ip_cnt -= 1
        end
        ip_cnt2 = r.variables[:visibility_level]
        while ip_cnt2 > 0
            imd_lvl = actor(r)
            ip_cnt = 0
            while ip_cnt < ip_cnt2
                imd_lvl = find_visibility_holder(w, imd_lvl)
                ip_cnt += 1
                do_activity!(w, :describing_locale, get_object(w, imd_lvl))
                ip_cnt2 -= 1
            end
        end
    end

    function check_arrival_rule(w::World, r::Rulebook)
        if r.variables[:visibility_level] == 0
            w.darkness_witnessed = true
        else
            visited(w, location(w.player))
        end
    end

    function other_people_looking(world::World, r::Rulebook)
        if actor(r) != id(world.player)
            print_name!(w, actor(r))
            sayln!(w, " looks around.")
        end
    end

    function det_vis_ceil(w::World, rb::Rulebook, ac::Action)
        ac.action_variables[:visibility_ceiling] = location(w.player)
        ac.action_variables[:visibility_level] = 1
        ac.action_variables[:room_describing_action] = :looking
    end
        
    look.action_variables[:room_describing_action] = look
    look.action_variables[:visibility_level] = 0
    look.action_variables[:visibility_ceiling] = nothing
    add_rule!(look.set_action_variables, :determine_visibility_ceiling, det_vis_ceil)
    c = look.carry_out_rules
    add_rule!(c, :room_description_heading, desc_heading_rule, false)
    add_rule!(c, :room_description_body, desc_body_rule, false)
    add_rule!(c, :room_description_paragraphs_about_objects, desc_obj_rule, false)
    add_rule!(c, :check_new_arrivals, check_arrival_rule, false)
    add_rule!(look.report_rules, :other_people_looking, other_people_looking)

    look
end
export create_looking!

@register_attribute single_named
@register_attribute plural_named
@register_attribute proper_named
@register_attribute improper_named
@register_attribute name_plurality
@register_attribute understand_as
@register_attribute indefinite_article

@register_attribute opposite

@register_attribute lighted_attr
@register_attribute visited_attr
@register_attribute visited
@register_attribute unvisited
@register_attribute lighted
@register_attribute dark
@register_attribute located_at

@register_attribute lit_attr
@register_attribute lit
@register_attribute unlit
@register_attribute edible_attr
@register_attribute edible
@register_attribute inedible
@register_attribute fixed_in_place
@register_attribute portable_attr
@register_attribute portable
@register_attribute wearable
@register_attribute wearable_attr
@register_attribute not_wearable
@register_attribute description
@register_attribute location
@register_attribute pushable_between
@register_attribute pushable_between_rooms
@register_attribute not_pushable_between_rooms
@register_attribute handled_attr
@register_attribute handled
@register_attribute not_handled
@register_attribute described_attr
@register_attribute described
@register_attribute not_described
@register_attribute mentioned_attr
@register_attribute mentioned
@register_attribute not_mentioned
@register_attribute listing_marked
@register_attribute marked_for_listing
@register_attribute unmarked_for_listing
@register_attribute initial_appearance
end