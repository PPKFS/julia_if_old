#using .StandardRules
using Test, Printf, InteractiveFiction
using TestSetExtensions

function ex2()
    #toggle_dbg!()
    function run_checks(w, rb)
        for thing in w.objects_by_type[:thing]
            if description(thing) == ""
                sayln!(w, @sprintf "%s has no description." name(thing))
            end
        end
    end
    w = make_blank_world("Bic")
    when_play_begins!(w, :run_through_property_checks_at_the_start_of_play, run_checks)
    staffroom = add_room!(w, "Staff Break Room", :dark)
    orange = add_thing!(w, "orange"; description="It's a small hard pinch-skinned thing from the lunch room,
            probably with lots of pips and no juice.")
    pen = add_thing!(w, "Bic pen")
    napkin = add_thing!(w, "napkin"; description="Slightly crumpled")
    #world.now_player_carries(orange, pen, napkin)
    out = run_world!(w)
    out
end

function ex4()
    w = make_blank_world("Slightly Wrong")
    awning = add_room!(w, "Awning"; description="A tan awning is stretched on tent poles over the dig-site, providing a little shade to " *
    "the workers here; you are at the bottom of a square twenty feet on a side, marked out with pegs and lines of string. " *
    "Uncovered in the south face of this square is an awkward opening into the earth.")
    slightlywrong = add_room!(w, "Slightly Wrong Chamber"; description=DynamicString(w, 
    "{main_description}A mural on the far wall depicts a woman with a staff,
    tipped with a pine-cone. She appears to be watching you.",
    Dict("main_description" => _ ->
    slightlywrong |> unvisited ? "When you first step into the room, you are bothered by the sense that
    something is not quite right: perhaps the lighting, perhaps the angle of the
    walls." : "")), map_connections=Dict(:south_of => awning))
    run_world!(w)
    #test_with_actions(world, ["looking", ["going", "south"], "looking"])
    #finish_up_world()
    #world
end

@testset ExtendedTestSet "Chapter 3: Things" begin
    @test ex2() == 
    "-----------------
-------Bic-------
-----------------


Staff Break Room

Bic pen has no description."
    #@test ex3()
end