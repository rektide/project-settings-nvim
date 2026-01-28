please help me define this project. i want to make `nvim-project-config`, a library for neovim that loads configuration based on the current project. so if we are in ~/src/rad-project/test , it will do three things:

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
