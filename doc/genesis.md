please help me define and architect this project. i want to make `nvim-project-config`, a library for neovim that loads configuration based on the current project. so if we are in ~/src/rad-project/test , it will do three things:

1. find the project name (`rad`), using a configurable directory walking strategy, falling back to cwd. the default strategy walks directories up. it is configured with matchers that look for .git folder.
2. and it will load configuration from a config directory using that file name. configuration comes in many ways. the config directory is also a configurable parameter, either a string or function. generally most configuration should allow for explicit setting, or a function that can generate the value. by default we have a function that returns vim.fn.stdpath("config") plus `projects`. there are various types of config, directories, lua, nvim, json. we have a pluggable configuration loader we run, providing our context object with our config directory & project name to it. this finds files to execute. finder is an configurable function passed a context object (of the project name and config directory), an object used throughout execution. the default finder is composed of a simpler finder, called twice: once for the `.` directory (meaning hte project config directory) and once for the project-name subdirectory thereof. the simpler finder also has a file-name matcher, which by default looks for project-name.lua .vim or .json; the same matcher is used for both simple matchers by the combined finder.
3. the next stage is an executor. there is again a composite pattern at play: the default executor is made of a lua/vim executor that runs the found scripts. and there is a json executor, that loads and caches a json file and exposes reading/writing to it programmatically. the composite's default configuration is to run both, but is configured based on file extension for what executors to run, accepting either a single string or matcher, or a list of strings and/or matchers. this is a common pattern for all matching we want to use throughout: single or list, string or matcher. the json settings need to be cached in memory. before writing or reading, we need to check the file write time for the json, and re-load it before doing work if the write time has changed. we need to test to make sure file write time is working on load, and if that fails, we need to assume dirty cache every time. please write a README.md that describes the ergonomic / developer experience of using this library we are designing.

## code design:

- we prefer asynchronous. we use plenary and especially plenary.async
- separation of concerns, making good use of different files to express the structure of the project via the filesystem

## Readme contents

- good very concise opening introduction to this project.
- a longer introduction, re-iterating what we are solving and trying to help with, and connecting to what this library does and is for
- we want a concise explanation of the architecture.
  - broad mermaid diagram to talk to
- we want a short then detailed configuration section. there is a lot to configure here & design here is crucial to the user/developer experience.
  - showing the default config fully elaborated should bring clarity to the nature of the system & help document the full config.
  - there's still more config like how matchers is a flexible concept
- we want a run through of the file structure
- a longer review of the architecture & detailing each piece
  - mermaid diagrams suggested

and whatever else you see fit!

start with your first pass. write it to a file. then discuss, and help figure out how we architect and shape this topic. you have the floor for discussion here; what areas topics clarity or refinements might we talk about to advance this document & architecture?

# resolved / additional decisions

based off initial findings, the following design decisions are to be encorporated:

- callback based usage patterns for async behaviors
- loading / watching configuration options:
  - option to do nothing at startup
  - option to watch for directory changes (and clear/ re-run settings on change)
  - option to watch for buffer changes (and clear/ re-run settings on change)
- two caches:
  - directory cache that wraps plenary.ls_async, and which stores all results. walking always reads-through this cache.
  - a file cache, holding file contents on read
    - file name, content, modified time all kept on file
    - file cache is write through, writes to cache go to files
    - items in file cache can have additional data attached to them, as .json field for the lua tables representing json.
    - writer to file cache is responsible for writing both .json and raw file data
    - reads from file cache, if file is modified, must eliminate any additional fields (or replace object entirely with a fresh one)
  - both caches use modified file time strategy to check if they need to regenerate the cache before yielding results.
- context is mutable. context is just the config. is mutable.
- pipeline is now by default these stages: walk, detect root, find files, execute files.
  - pipeline is an arbitrary pluggable system. could be other configs.
  - each stage is invoked with context, one input item, and it's stage number
  - each stage calls the next stage each time it has an output
  - question: how do we detect when pipeline is done?
- general philosophy of run everything, merge, with last file / late comer winning
- walk walks upwards, from root directory towards the project, yielding each directory as a project
  - has optional matcher, but usually empty: just fire for each directory as we walk up to current directory
  - alternate unused implementation walks down until it finds git, project root finder
- detect root passes through all data, but runs matcher.
  - sets a single project root on config/context when matches
  - has an override setting, default off, to override existing project root
- find directories looks in `vim.fn.stdpath("config")` for the project name
- default executor is a router that routes to file-type specific executors, which register the file types they support: .vim .lua .json
- vim/lua executor just run the vim/lua
- json executor keeps track of all json files seen.
  - it merges json together, with most recent file taking priority.
  - writes go to the project root json, create if needed.
- project names can be nested. this is primarily to support repositories with sub-packages. repo/package is recommended. additional depth is ok but discouraged.
- find_files is called multiple times, with context and project name. generates multiple results.
- a variety of composable tools are available for files: a 'not' filter, such as for
- clear resets only some elements of context:
  - project root (let get re-found)
  - synthesized json object
  - question: what actually happens? hardcoded clear? event? recreate pipeline elements afresh?
- matcher processor takes string/single item, string, matcher/regex, or function. or's them together. `and` and `not` utility wrappers also provided.


