import Git: git

run(`$(git()) config --global user.name "Johnathan Bizzano"`)
run(`$(git()) config --global user.email "bizzanoj@my.erau.edu"`)

const repo_user = "HyperSphereStudio"

const mousetrap_commit = "b66a2599d10642991c5a9fc983f69b2caef15cf1"
const mousetrap_julia_binding_commit = "8d3b3491e997b4d8286876f8986ff84d5b89d5dd"
#const mousetrap_julia_binding_commit = "1e1944c4391e1f8e0f90e23f60d5463dd19a2ea6"

const VERSION = "0.4.5"
const deploy_local = false
const skip_build = false
const tarball_name = "build_tarballs"

#Delete Past Product Directory
	
if !skip_build
	rm("products", recursive=true)
end

if deploy_local
    @info "Deployment: local"
    repo = "local"
else
    @info "Deployment: github"
    repo = "$repo_user/libmousetrap_jll"
end

## Configure

function configure_file(path_in::String, path_out::String)
    file_in = open(path_in, "r")
    file_out = open(path_out, "w+")

    for line in eachline(file_in)
        write(file_out, replace(line,
			"@MOUSETRAP_REPO_USER@" => repo_user,
            "@MOUSETRAP_COMMIT@" => mousetrap_commit,
            "@MOUSETRAP_JULIA_BINDING_COMMIT@" => mousetrap_julia_binding_commit,
            "@MOUSETRAP_VERSION@" => VERSION
        ) * "\n")
    end

    close(file_in)
    close(file_out)
end

@info "Configuring `$tarball_name.jl.in`"
configure_file("./$tarball_name.jl.in", "./$tarball_name.jl")

path = joinpath(Sys.BINDIR, "../dev/mousetrap_jll")
if isfile(path)
    run(`rm -r $path`)
end

if skip_build
	run(`julia -t 8 $tarball_name.jl --debug --skip-build --verbose --deploy=$repo`)
else 
	run(`julia -t 8 $tarball_name.jl --debug --verbose --deploy=$repo`)
end
