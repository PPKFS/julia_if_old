using Parameters
include("macros.jl")

const Optional{F} = Union{F,Nothing}

struct ObjectGraphNode
    type::Symbol
    children::Vector{ObjectGraphNode}
    parents::Vector{ObjectGraphNode}
    attributes::Set{Symbol}
end

const ObjectGraph = Dict{Symbol, ObjectGraphNode}

struct Object
    type::Symbol
    name::String
    id::Symbol
    attrs::Dict{Symbol, Any}
    world
end

struct Rule
    name::Symbol
    rule::Function
    any_actor::Bool
end

struct AliasOf
    attr::Symbol
    other::Symbol
end

struct Rulebook
    name::Symbol
    default_outcome::Optional{Any}
    first_rules::Vector{Rule}
    rules::Vector{Rule}
    last_rules::Vector{Rule}
    variables::Dict{Symbol,Any}
end

struct Activity
    name::Symbol
    before_rules::Rulebook
    carry_out_rules::Rulebook
    after_rules::Rulebook
    activity_variables::Dict{Symbol, Any}
end

mutable struct Action
    name::Symbol
    understand_as::Vector{String}
    applies_to::Int64
    set_action_variables::Rulebook
    before_rules::Rulebook
    check_rules::Rulebook
    carry_out_rules::Rulebook
    report_rules::Rulebook
    action_variables::Dict{Symbol, Any}
end

@with_kw mutable struct World
    message_indent::Int64 = 0
    print_counter::Int64 = 0
    object_hierarchy::ObjectGraph = Dict()
    attribute_store::Dict{Symbol, Union{Dict{Symbol, Any}, Set{Any}}} = Dict()
    objects::Dict{Symbol, Object} = Dict()
    objects_by_type::Dict{Symbol, Vector{Object}} = Dict()
    rulebooks::Dict{Symbol, Rulebook} = Dict()
    title::String = ""
    active_rulebook::Vector{Rulebook} = []
    player::Optional{Object}
    first_room::Optional{Object}
    actions::Dict{Symbol, Action} = Dict()
    activities::Dict{Symbol, Activity} = Dict()
    room_descriptions::Symbol = :sometimes_abbreviated
    darkness_witnessed::Bool = false
end

struct DynamicString
    str::String
    subs::Dict{String,Function}
    world::World
    function DynamicString(w::World, str2::String, s::Dict)
        str = str2
        world = w
        subs = Dict()
        for k in keys(s)
            subs[string("{", k, "}")] = s[k]
        end
        new(str, subs)
    end
end

const Text = Union{String, DynamicString}
