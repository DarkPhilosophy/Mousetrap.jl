using mousetrap_jll
using Mousetrap
using ModernGL, GLMakie, Colors, GeometryBasics, ShaderAbstractions
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor, to_screen_postprocessor
using GLMakie.GLAbstraction
using GLMakie.Makie

const screens = Dict{UInt64, GLMakie.Screen}()

mutable struct GLMakieArea <: Widget

    glarea::GLArea
    framebuffer_id::Ref{Int}
    framebuffer_size::Vector2i

    function GLMakieArea()
        glarea = GLArea()
        set_auto_render!(glarea, false)
        connect_signal_render!(on_makie_area_render, glarea)
        connect_signal_resize!(on_makie_area_resize, glarea)
        return new(glarea, Ref{Int}(0), Vector2i(0, 0))
    end
end
Mousetrap.get_top_level_widget(x::GLMakieArea) = x.glarea

function GLMakie.resize_native!(native::GLMakieArea, resolution...)
    # noop, ignore makie size request to not interfere with widget layout manager
end

function on_makie_area_render(self, context)
    key = Base.hash(self)
    if haskey(screens, key)
        screen = screens[key]
        if !isopen(screen) return false end
        screen.render_tick[] = nothing
        glarea = screen.glscreen
        glarea.framebuffer_id[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
        GLMakie.render_frame(screen) 
    end
    return true
end

function on_makie_area_resize(self, w, h)
    key = Base.hash(self)
    if haskey(screens, key)
        screen = screens[key]
        glarea = screen.glscreen
        glarea.framebuffer_size.x = w
        glarea.framebuffer_size.y = h
        queue_render(glarea.glarea)
    end
    return nothing
end

function GLMakie.window_size(w::GLMakieArea)
    size = get_natural_size(w)
    size.x = size.x * GLMakie.retina_scaling_factor(w)
    size.y = size.y * GLMakie.retina_scaling_factor(w)
    return (size.x, size.y)
end
GLMakie.framebuffer_size(self::GLMakieArea) = (self.framebuffer_size.x, self.framebuffer_size.y)

function GLMakie.was_destroyed(window::GLMakieArea)
    return !get_is_realized(window)
end

function Base.isopen(w::GLMakieArea)
    return !GLMakie.was_destroyed(w)
end

function GLMakie.set_screen_visibility!(screen::GLMakieArea, bool)
    if bool 
        show!(screen.glarea)
    else
        hide!(screen.glarea)
    end
end

function GLMakie.apply_config!(screen::GLMakie.Screen{GLMakieArea}, config::GLMakie.ScreenConfig; start_renderloop=true) 
    @warning "In MousetrapMakie: GLMakie.apply_config!: This feature is not yet implemented, ignoring config"
    return screen
end

function Makie.colorbuffer(screen::GLMakie.Screen{GLMakieArea}, format::Makie.ImageStorageFormat = Makie.JuliaNative)

    ShaderAbstractions.switch_context!(screen.glscreen)
    ctex = screen.framebuffer.buffers[:color]
    if size(ctex) != size(screen.framecache)
        screen.framecache = Matrix{RGB{Colors.N0f8}}(undef, size(ctex))
    end
    GLMakie.fast_color_data!(screen.framecache, ctex)
    if format == Makie.GLNative
        return screen.framecache
    elseif format == Makie.JuliaNative
        img = screen.framecache
        return PermutedDimsArray(view(img, :, size(img, 2):-1:1), (2, 1))
    end
end

function Base.close(screen::GLMakie.Screen{GLMakieArea}; reuse = true)
    GLMakie.set_screen_visibility!(screen, false)
    GLMakie.stop_renderloop!(screen; close_after_renderloop=false)
    if screen.window_open[]
        screen.window_open[] = false
    end
    if !GLMakie.was_destroyed(screen.glscreen)
        empty!(screen)
    end
    if reuse && screen.reuse
        push!(SCREEN_REUSE_POOL, screen)
    end
    glarea = screen.glscreen
    delete!(screens, hash(glarea))      
    close(toplevel(screen.glscreen))
    return
end

ShaderAbstractions.native_switch_context!(a::GLMakieArea) = make_current(a.glarea)
ShaderAbstractions.native_context_alive(x::GLMakieArea) = get_is_realized(x)

function GLMakie.destroy!(w::GLMakieArea)
    # noop, lifetime is managed by mousetrap instead
end
    
function create_glmakie_screen(area::GLMakieArea; screen_config...)

    if !get_is_realized(area) 
        log_critical("MousetrapMakie", "In MousetrapMakie.create_glmakie_screen: GLMakieArea is not yet realized, it's internal OpenGL context cannot yet be accessed")
    end

    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    if config.fullscreen
        # noop
    end

    set_is_visible!(area, config.visible)
    set_expand!(area, true)

    shader_cache = GLAbstraction.ShaderCache(area)
    ShaderAbstractions.switch_context!(area)
    fb = GLMakie.GLFramebuffer((1, 1)) # resized on GLMakieArea realization later

    postprocessors = [
        config.ssao ? ssao_postprocessor(fb, shader_cache) : empty_postprocessor(),
        OIT_postprocessor(fb, shader_cache),
        config.fxaa ? fxaa_postprocessor(fb, shader_cache) : empty_postprocessor(),
        to_screen_postprocessor(fb, shader_cache, area.framebuffer_id)
    ]

    screen = GLMakie.Screen(
        area, shader_cache, fb,
        config, false,
        nothing,
        Dict{WeakRef, GLMakie.ScreenID}(),
        GLMakie.ScreenArea[],
        Tuple{GLMakie.ZIndex, GLMakie.ScreenID, GLMakie.RenderObject}[],
        postprocessors,
        Dict{UInt64, GLMakie.RenderObject}(),
        Dict{UInt32, Makie.AbstractPlot}(),
        false,
    )

    hash = Base.hash(area.glarea)
    screens[hash] = screen
    println("register: $hash")
    
    set_tick_callback!(area.glarea) do clock::FrameClock
        if GLMakie.requires_update(screen)
            queue_render(area.glarea)
        end

        if GLMakie.was_destroyed(area)
            return TICK_CALLBACK_RESULT_DISCONTINUE
        else
            return TICK_CALLBACK_RESULT_CONTINUE
        end
    end

    return screen
end

Makie.disconnect!(window::GLMakieArea, f) = nothing
Makie.window_open(scene::Scene, window::GLMakieArea) = nothing

function Makie.window_area(scene::Scene, screen::GLMakie.Screen{GLMakieArea})
    area = scene.events.window_area
    dpi = scene.events.window_dpi
    glarea = screen.glscreen

    function on_resize(self, w, h)
        dpi[] = Mousetrap.calculate_monitor_dpi(glarea)
        area[] = Recti(0, 0, w, h)
        return nothing
    end

    connect_signal_resize!(on_resize, glarea.glarea)
    queue_render(glarea.glarea)
end

function GLMakie.retina_scaling_factor(window::GLMakieArea)
    return Mousetrap.get_scale_factor(window.glarea)
end

GLMakie.pollevents(::GLMakie.Screen{GLMakieArea}) = nothing
Makie.mouse_buttons(scene::Scene, glarea::GLMakieArea) = nothing
Makie.keyboard_buttons(scene::Scene, glarea::GLMakieArea) = nothing
Makie.dropped_files(scene::Scene, window::GLMakieArea) = nothing
Makie.unicode_input(scene::Scene, window::GLMakieArea) = nothing
Makie.mouse_position(scene::Scene, screen::GLMakie.Screen{GLMakieArea}) = nothing
Makie.scroll(scene::Scene, window::GLMakieArea) = nothing
Makie.hasfocus(scene::Scene, window::GLMakieArea) = nothing
Makie.entered_window(scene::Scene, window::GLMakieArea) = nothing

mutable struct MakieCanvas <: Widget
    area::GLMakieArea
    screen::Ref{Union{GLMakie.Screen{GLMakieArea}, Nothing}}

    function MakieCanvas()
        area = GLMakieArea()
        out = new(area, nothing)
        connect_signal_realize!(on_makie_canvas_realize, area.glarea, out)
        return out
    end
end
Mousetrap.get_top_level_widget(x::MakieCanvas) = x.area

function on_makie_canvas_realize(self::GLArea, out::MakieCanvas)
    make_current(self)
    out.screen[] = create_glmakie_screen(out.area)
    return nothing
end

main() do app::Application
    window = Window(app)
    canvas = MakieCanvas()
    set_size_request!(canvas, Vector2f(200, 200))
    set_child!(window, canvas)
    connect_signal_show!(window) do self::Window
        display(canvas.screen[], scatter(1:4))
        return nothing
    end
    present!(window)
end