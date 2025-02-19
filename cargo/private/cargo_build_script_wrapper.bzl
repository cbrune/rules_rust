"""Rules for Cargo build scripts (`build.rs` files)"""

load(
    "//cargo/private:cargo_build_script.bzl",
    "name_to_crate_name",
    "name_to_pkg_name",
    _build_script_run = "cargo_build_script",
)
load("//rust:defs.bzl", "rust_binary")

# List of kwargs that only apply to running the build script
build_script_only_kwargs = [
    "compatible_with",
    "build_script_env_file",
]

def cargo_build_script(
        name,
        crate_features = [],
        version = None,
        deps = [],
        build_script_env = {},
        data = [],
        tools = [],
        links = None,
        rustc_env = {},
        rustc_flags = [],
        visibility = None,
        tags = None,
        **kwargs):
    """Compile and execute a rust build script to generate build attributes

    This rules take the same arguments as rust_binary.

    Example:

    Suppose you have a crate with a cargo build script `build.rs`:

    ```output
    [workspace]/
        hello_lib/
            BUILD
            build.rs
            src/
                lib.rs
    ```

    Then you want to use the build script in the following:

    `hello_lib/BUILD`:
    ```python
    package(default_visibility = ["//visibility:public"])

    load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library")
    load("@rules_rust//cargo:defs.bzl", "cargo_build_script")

    # This will run the build script from the root of the workspace, and
    # collect the outputs.
    cargo_build_script(
        name = "build_script",
        srcs = ["build.rs"],
        # Optional environment variables passed during build.rs compilation
        rustc_env = {
           "CARGO_PKG_VERSION": "0.1.2",
        },
        # Optional environment variables passed during build.rs execution.
        # Note that as the build script's working directory is not execroot,
        # execpath/location will return an absolute path, instead of a relative
        # one.
        build_script_env = {
            "SOME_TOOL_OR_FILE": "$(execpath @tool//:binary)"
        }
        # Optional data/tool dependencies
        data = ["@tool//:binary"],
    )

    rust_library(
        name = "hello_lib",
        srcs = [
            "src/lib.rs",
        ],
        deps = [":build_script"],
    )
    ```

    The `hello_lib` target will be build with the flags and the environment variables declared by the \
    build script in addition to the file generated by it.

    Args:
        name (str): The name for the underlying rule. This should be the name of the package
            being compiled, optionally with a suffix of `_build_script`.
        crate_features (list, optional): A list of features to enable for the build script.
        version (str, optional): The semantic version (semver) of the crate.
        deps (list, optional): The dependencies of the crate.
        build_script_env (dict, optional): Environment variables for build scripts.
        data (list, optional): Files needed by the build script.
        tools (list, optional): Tools (executables) needed by the build script.
        links (str, optional): Name of the native library this crate links against.
        rustc_env (dict, optional): Environment variables to set in rustc when compiling the build script.
        rustc_flags (list, optional): List of compiler flags passed to `rustc`.
        visibility (list of label, optional): Visibility to apply to the generated build script output.
        tags: (list of str, optional): Tags to apply to the generated build script output.
        **kwargs: Forwards to the underlying `rust_binary` rule. An exception is the `compatible_with`
            attribute, which shouldn't be forwarded to the `rust_binary`, as the `rust_binary` is only
            built and used in `exec` mode. We propagate the `compatible_with` attribute to the `_build_scirpt_run`
            target.
    """

    # This duplicates the code in _cargo_build_script_impl because we need to make these
    # available both when we invoke rustc (this code) and when we run the compiled build
    # script (_cargo_build_script_impl). https://github.com/bazelbuild/rules_rust/issues/661
    # will hopefully remove this duplication.
    rustc_env = dict(rustc_env)
    if "CARGO_PKG_NAME" not in rustc_env:
        rustc_env["CARGO_PKG_NAME"] = name_to_pkg_name(name)
    if "CARGO_CRATE_NAME" not in rustc_env:
        rustc_env["CARGO_CRATE_NAME"] = name_to_crate_name(name_to_pkg_name(name))

    binary_tags = [tag for tag in tags or []]
    if "manual" not in binary_tags:
        binary_tags.append("manual")
    build_script_kwargs = {}
    binary_kwargs = kwargs

    for k in build_script_only_kwargs:
        if k in kwargs:
            build_script_kwargs[k] = kwargs[k]
            binary_kwargs.pop(k)

    if "toolchains" in kwargs:
        build_script_kwargs["toolchains"] = kwargs["toolchains"]

    rust_binary(
        name = name + "_",
        crate_features = crate_features,
        version = version,
        deps = deps,
        data = data,
        rustc_env = rustc_env,
        rustc_flags = rustc_flags,
        tags = binary_tags,
        **binary_kwargs
    )
    _build_script_run(
        name = name,
        script = ":{}_".format(name),
        crate_features = crate_features,
        version = version,
        build_script_env = build_script_env,
        links = links,
        deps = deps,
        data = data,
        tools = tools,
        rustc_flags = rustc_flags,
        visibility = visibility,
        tags = tags,
        **build_script_kwargs
    )
