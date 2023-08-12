# Hotpot Cookbook

<!-- panvimdoc-ignore-start -->

## I want to...

- [Include some common functions, macros or prelude in all files](#preprocessing).
- Compile into the `lua/` directory
  - on demand by [colocation](#colocation) or,
  - everything [ahead of time](#ahead-of-time-compilation).
- Write `init.lua` as `init.fnl`
- [Write an config `ftplugin`](#write-an-ftplugin).
- See the output of
  - a fennel file or,
  - some arbitary fennel code.
- Write a Neovim plugin in fennel

<!-- panvimdoc-ignore-end -->

## Preprocessing

You may set the `hotpot.setup({preprocessing = ...})` option to a function that
receives the source code to be compiled and returns it with any alterations.

The function receives the following arguments:

- The fennel source code to be compiled, as a string.
- A table containing:
  - `path`: the path of the file being compiled,
  - `modname`: the name of the module being compiled and
  - `macro?`: a boolean indicating whether the file is being compiled as a macro or not.

The function must return the source code to compile.

Note that in some contexts, `path` and `modname` may be nil, such as when
running fennel code via the API. It's recommended you check the path strictly.

Ex.

```fennel
(fn [src {: path : modname : macro?}]
  (if (and path modname (path:match "config/nvim"))
    (let [head (-> (table.concat ["(import-macros {: defmodule} :my.macros)"
                                  "(defmodule %s"] :\n)
                   (string.format modname))
          tail ")"]
      (.. head src tail))
    ;; remember to return the source in other cases
    (values src)))
```

## Colocation

Colocation changes where Hotpot places the compiled lua files.

Normally, given `~/dir/fnl/mod.fnl`, the resulting lua file would be placed at
`~/.cache/.../dir/lua/mod.lua`. This keeps the `lua/` directory unpolluted by
"generated files".

When colocation is enabled, instead the file would be placed at
`~/dir/lua/mod.lua`, it is "colocated" in the same parent directory.

You can enable colocation by creating a `.hotpot.lua` file in the project root
(the same directory that has `fnl/` and `lua/` in it), i.e. `~/dir/.hotpot.lua`
in the previous example.

The file should return a table of settings, where `colocate` can be `true` or
`false` (default).

Ex.

```lua
return {
  colocate = true
}
```

Colocation is most useful when writing plugins that have lua code in `lua/` for
distribution. Due to Hotpots [module load order
preference](#module-load-order-preference), it will prefer loading these over
the `fnl/` code. By enabling colocation, Hotpot will instead overwrite these
`lua/` files if required.

There are some important things to keep in mind:

- For safety, colocation only applies to files under the `fnl/` and `lua/` directories.
- It only takes effect when the module is loaded via `require`.
  - You may not see any effect if `package.loaded` already contains an entry
  for your module!
  - If you are writing a plugin, you should take some steps to ensure all your
  modules have been required, or use something like `hotpot.api.make` to build
  your release.
- Hotpot takes care not to overwrite any changes you may have made to the lua
files. It should prompt you before taking any action but be warned if you are
working out of both directories simultaneously.
- It can currently only be applied to the `fnl/` and `lua/` directories as a
whole.

## Ahead of time compilation

You can compile code ahead of time with the `hotpot.api.make` module. This can
be used to build fennel plugins for distribution, or if you want to compile
your config.

The module currently provides two functions: `build` and `check` (functionally
equivalent `build` but with no changes to disk).

`build` accepts a `source-path` (directory or single file), an optional
`options` table and then a set of `pattern function` argument pairs.

Each `*.fnl` file in `source-dir` is checked against each `pattern` given, and
if any match the `function` is called with the pattern captures as arguments.

The function should return a path to save the compiled file to, or `nil`.

Ex.

```fennel
;; build all fnl files inside config dir
;; Note you could also pass "." or some expanded vim variable
(local {: build} (require :hotpot.api.make))
(build "~/.config/nvim"
       ;; ~/.config/nvim/fnl/*.fnl -> ~/.config/nvim/lua/*.lua
       "(.+)/fnl/(.+)"
       ;; `root` is the first match, `path` is the second.
       ;; "(.+)/fnl/(.+)"
       ;;  ^^^^ root
       ;;           ^^^^ path
       ;; Note that the argument names are not important, you decide
       ;; what to call them, in the order they are captured.
       (fn [root path {: join-path}]
         ;; ignore our own macro file (init-macros.fnl is ignored by default)
         (if (not (string.match path "my-macros%.fnl$"))
           ;; join-path automatically uses the os-appropriate path separator
           (join-path root :lua path)))
       ;; config/ftplugins/*.fnl -> config/ftplugins/*.lua
       "(~/.config/nvim/ftplugins/.+)"
       ;; Note again, we have 1 capture, so only one arg, and since we're not
       ;; manipulating the path we can ignore the helpers table too.
       (fn [whole-path] (values whole-path)))
```

You may put the above code in a file such as `build.fnl` then run it with
`:Fnlfile build.fnl` (or `:Fnlfile %` if its your current buffer).

You may also attach a autocommand via an `ftplugin` and the `BufWritePost`
event to build on save.

For complete documentation, see [`:h hotpot.api.make`](doc/hotpot-api.txt).

## Writing `~/.config/nvim/init.lua` in Fennel

We can use a combination of the Make API and LibUV to write our main `init.lua`
in Fennel and automatically compile it to loadable lua on save.

```fennel
;; ~/.config/nvim/init.fnl

(fn build-init []
  (let [{: build} (require :hotpot.api.make)
        ;; by default, Fennel wont perform strict global checking when
        ;; compiling but we can force it to check by providing a list
        ;; of allowed global names, this can catch some additional errors in
        ;; this file.
        allowed-globals (icollect [n _ (pairs _G)] n)
        opts {:verbosity 0 ;; set to 1 (or dont inclued the key) to see messages
              :compiler {:modules {:allowedGlobals allowed-globals}}}]
    ;; just pass back the whole path as is
    (build "~/.config/nvim/init.fnl" opts ".+" #(values $1))))

(let [hotpot (require :hotpot)
      setup hotpot.setup
      build hotpot.api.make.build
      uv vim.loop]
  ;; do some configuration stuff
  (setup {:provide_require_fennel true
          :compiler {:modules {:correlate true}
                     :macros {:env :_COMPILER
                              :compilerEnv _G
                              :allowedGlobals false}}})

  ;; watch this file for changes and auto-rebuild on save
  (let [handle (uv.new_fs_event)
        ;; uv wont accept condensed paths
        path (vim.fn.expand "~/.config/nvim/init.fnl")]
    ;; note the vim.schedule call
    (uv.fs_event_start handle path {} #(vim.schedule build-init))
    ;; close the uv handle when we quit nvim
    (vim.api.nvim_create_autocmd :VimLeavePre {:callback #(uv.close handle)})))

(require :the-rest-of-my-config)
```

Finally, we have to manually run this code *once* to generate the new `init.lua`:

- Open `init.fnl`
- Run `:Fnlfile %` to execute the current file and *enable* the file watcher.
  - Note, this will also run any code that is executed by `(require
    :the-rest-of-my-config)`.
- Save the file with `:w` to *run* the file watcher.
  - *This will overwrite your existing `init.lua`!*
- Open `init.lua` to confirm it contains your fennel, compiled into lua.
- Start neovim in a new terminal to confirm the config loading is functioning
  without any errors.

## Write an ftplugin

Put your code in `~/.config/nvim/ftplugin` as you would any lua ftplugin.

Ex.

```fennel
;;~/.config/nvim/ftplugin/fennel.fnl
(print (vim.fn.expand :<afile>)) ;; print name of fennel file
(vim.opt.formatoptions:append :j)
```

> ftplugins are put in the cache, irrespective of any colocation setting. This is
> to avoid any module precedence issues.

## Using Hotpot Reflect

<!-- panvimdoc-ignore-start -->

<div align="center">
<p align="center">
  <img style="width: 80%" src="images/reflect.svg">
</p>
</div>

<!-- panvimdoc-ignore-end -->

*!! The Reflect API is experimental and its shape may change, particularly around
accepting ranges instead of requiring a visual selection and some API terms
such as what a `session` is. !!*

*!! Do NOT run dangerous code (like `(system "rm -rf /")` inside an evaluation
block! You could cause massive damage to your system! !!*

*!! Some plugins (Parinfer) can be quite destructive to the buffer and can cause
marks to be lost or damaged. In this event you can just reselect your range. !!*

Reflect API acts similarly to a REPL environment but instead of entering
statements in a conversational manner, you mark sections of your code and the
API will "reflect" the result to you and update itself as you change your
code.

The basic usage of the API is:

1. Get an output buffer pass it to `attach-output`. A `session-id` is returned.

2. Visually select a region of code and call `attach-input session-id <buf>`
where buf is probably `0` for current buffer.

Note that windowing is not mentioned. The Reflect API leaves general window
management to the user as they can best decide how they wish to structure their
editor - with floating windows, splits above, below, etc. The Reflect API also
does not provide any default bindings.

The following is an example binding setup that will open a new window and
connect the output and inputs with one binding. It tracks the session and only
allows one per-editor session. This code is written verbosely for education and
could be condensed.

```fennel
;; Open session and attach input in one step.
;; Note the complexity here is mostly due to nvim not having an api to create a
;; split window, so we must shuffle some code to create a buf, pair input and output
;; then put that buf inside a window.
(local reflect-session {:id nil :mode :compile})
(fn new-or-attach-reflect []
  (let [reflect (require :hotpot.api.reflect)
        with-session-id (if reflect-session.id
                          (fn [f]
                            ;; session id already exists, so we can just pass
                            ;; it to whatever needs it
                            (f reflect-session.id))
                          (fn [f]
                            ;; session id does not exist, so we need to create
                            ;; an output buffer first then we can pass the
                            ;; session id on, and finally hook up the output
                            ;; buffer to a window
                            (let [buf (api.nvim_create_buf true true)
                                  id (reflect.attach-output buf)]
                              (set reflect-session.id id)
                              (f id)
                              ;; create window, which will forcibly assume focus, swap the buffer
                              ;; to our output buffer and setup an autocommand to drop the session id
                              ;; when the session window is closed.
                              (vim.schedule #(do
                                               (api.nvim_command "botright vnew")
                                               (api.nvim_win_set_buf (api.nvim_get_current_win) buf)
                                               (api.nvim_create_autocmd :BufWipeout
                                                                        {:buffer buf
                                                                         :once true
                                                                         :callback #(set reflect-session.id nil)}))))))]
    ;; we want to set the session mode to our current mode, and attach the
    ;; input buffer once we have a session id
    (with-session-id (fn [session-id]
                       ;; we manually set the mode each time so it is persisted if we close the session.
                       ;; By default `reflect` will use compile mode.
                       (reflect.set-mode session-id reflect-session.mode)
                       (reflect.attach-input session-id 0)))))
(vim.keymap.set :v :hr new-or-attach-reflect)

(fn swap-reflect-mode []
  (let [reflect (require :hotpot.api.reflect)]
    ;; only makes sense to do this when we have a session active
    (when reflect-session.id
      ;; swap held mode
      (if (= reflect-session.mode :compile)
        (set reflect-session.mode :eval)
        (set reflect-session.mode :compile))
      ;; tell session to use new mode
      (reflect.set-mode reflect-session.id reflect-session.mode))))
(vim.keymap.set :n :hx swap-reflect-mode)
```

## Using the API

See [`:h hotpot.api`](doc/hotpot-api.txt) a complete listing.

Note: The API modules can be lazy-accessed from `hotpot` and `hotpot.api`

```fennel
(let [hotpot (require :hotpot)
      eval hotpot.api.eval]
  (eval.eval-selection))

(let [api (require :hotpot.api)
      compile api.compile]
  (compile.compile-buffer 0))
```

**Eval & Compile**

Evaluate or compile the `v` selection, or the entire buffer.

```fennel
(fn pecho [ok? ...]
  "nvim_echo vargs, as DiagnosticHint or DiagnosticError depending on ok?"
  (let [{: nvim_echo} vim.api
        {: view} (require :fennel)
        hl (if ok? :DiagnosticHint :DiagnosticError)
        list [...]
        output []]
    ;; TODO: this can be fcollect in fennel 1.2.0)
    (for [i 1 (select :# ...)]
      (table.insert output (-> (. list i)
                               (#(match (type $1)
                                   :table (view $1)
                                   _ (tostring $1)))
                               (.. "\n"))))
    (nvim_echo (icollect [_ l (ipairs output)] [l hl]) true {})))

(vim.keymap.set :n :heb
                #(let [{: eval-buffer} (require :hotpot.api.eval)]
                  (pecho (eval-buffer 0)))
               {:desc "Evaluate entire buffer"})

(vim.keymap.set :v :hes
                #(let [{: eval-selection} (require :hotpot.api.eval)]
                  (pecho (eval-selection)))
               {:desc "Evaluate selection"})

(vim.keymap.set :n :hcb
                #(let [{: compile-buffer} (require :hotpot.api.compile)]
                  (pecho (compile-buffer 0)))
               {:desc "Compile entire buffer"})

(vim.keymap.set :v :hcs
                #(let [{: compile-selection} (require :hotpot.api.compile)]
                  (pecho (compile-selection)))
               {:desc "Compile selection"})
```

**Cache operations**

Open the matching lua file for the current file.

```fennel
(vim.keymap.set :n :hff
                #(let [{: cache-path-for-fnl-file} (require :hotpot.api.cache)]
                   (match (cache-path-for-fnl-file (vim.fn.expand :%:p))
                     path (vim.cmd (.. ":new " path))
                     nil (vim.api.nvim_echo [["No cache file for current file" :WarningMsg]] true {})))
                {:desc "Open compiled lua file for current file"})
```

or with a Telescope searcher:

```fennel
(let [{: find_files} (require :telescope.builtin)
      {: cache-prefix} (require :hotpot.api.cache)]
  (find_files {:cwd (cache-prefix)
               :hidden true}))
```

Open the matching lua file for an arbitrary module.

```fennel
(vim.keymap.set :n :hfm
                #(let [{: cache-path-for-module} (require :hotpot.api.cache)
                       modname (vim.fn.input "module name: ")]
                   (match (cache-path-for-module modname)
                     path (vim.cmd (.. ":new " path))
                     nil (vim.api.nvim_echo [[(.. "No cache file for " modname) :WarningMsg]] true {})))
                {:desc "Open compiled lua file for module"})
```

## Commands

Commands to run snippets of Fennel, similar to Neovim's `:lua` et al commands.

- `:[range]Fnl {expression} -> evaluate range in buffer OR expression`
- `:[range]Fnldo {expression} -> evaluate expression for each line in range`
- `:Fnlfile {file} -> evaluate file`
- `:source {file} -> alias to :Fnlsource`, must be called as `:source
  my-file.fnl` or `:source %` and the given file must be a descendent of a
  `fnl` directory. Will attempt to recompile, recache and reload the given
  file.

Hotpot expects the user to specify most maps themselves via the API functions.
It does provide one `<Plug>` mapping for operator-pending eval.

```viml
map <Plug> ghe <Plug>(hotpot-operator-eval)
```

> gheip -> evaluate fennel code in paragraph


## Compiler Sandbox

Fennel compiles macros in a restricted environment called a sandbox. In this
environment, common lua tables such as `os`, or in Neovim, `vim` are
unavailable.

> Note: this restriction applies to code *executed in* the macro, not code
> *generated by* the macro.

As an example, imagine we want a function that prints the time *of
compilation*, we may write something like this:

```fennel
;; ts-fn.fnl

(macro fn-with-ts [name args body]
  (let [now (os.date :%s)]
    `(fn ,name ,args
      (do
       (print "code generated at" ,now)
       ,body))))

(fn-with-ts my-func [x]
  (print (* x x)))
```

If we try to build this with the Fennel CLI, we get the following error, because
`os` is unavailable:

```
$ fennel -c ts-fn.fnl
Compile error in ts-fn.fnl:2:13
  unknown identifier in strict mode: os

  (let [now (os.date :%s)]
* Try looking to see if there's a typo.
* Try using the _G table instead, eg. _G.os if you really want a global.
* Try moving this code to somewhere that os is in scope.
* Try binding os as a local in the scope of this code.
```

We can disable the compiler sandbox with `--no-compiler-sandbox`, which will
allow us to compile our code:

```
$ fennel --no-compiler-sandbox -c ts-fn.fnl
local function my_func(x)
  print("code generated at", "1665501877")
  return print((x * x))
end
return my_func
```

With this understanding, we can adjust the macro compilation options we provide
to `hotpot.setup`, and then we can use the function inside Neovim:

```lua
-- ...
macros = {
  env = "_COMPILER",
  compilerEnv = _G,
  allowGlobals = false,
}
-- ...
```

For more information on available options, see Fennels own documentation.

## Compiler Plugins

Fennel supports user provided compiler plugins and Hotpot does too. For more
information on compiler plugins, see Fennels own documentation.

Plugins are specified for both `modules` and `macros` and may be provided as a
table (ie. as described by Fennels documentation) or a module name as a string.

When your plugin requires access to the compiler environment or is
uncomfortable to write in lua (which may be the language your using to define
`setup`'s options), specifying the plugin as a string lets you do that.

Compiler plugins are extremely powerful and can let you add new language
constructs to Fennel or modify existing ones but be aware of the impact you
might have on portability and clarity.

Below are two identical plugins which add 1 to every `(+)` call (so `(+ 1 1)`
becomes `(+ 1 1 1)`.

```fennel
;; .config/nvim/fnl/off_by_one.fnl
(fn call [ast scope ...]
  (match ast
    [[:+]] (table.insert ast 1))
  (values nil))

{:name :add_one_module
 :call call
 :versions [:1.2.1]}
```

```lua
off_by_one = {
  name = "add_one_table",
  call = function (ast, scope)
    if ast[1][1] == "+" then
      table.insert(ast, 1)
    end
    return nil
  end,
  versions = {"1.2.1"}
}

require("hotpot").setup({
  compiler = {
    modules = {
      plugins = {
        "off_by_one",
        off_by_one,
      }
    },
    -- you may also define for macros
    -- macros = {
    --   plugins = {...},
    -- },
  }
})
```

<!-- panvimdoc-ignore-start -->

<details>
<summary>F͙̖͍͇̤ͣ̅ͯ̕Ō̝̦͎̣̲͖̬̬̌́R̖̮͈ͭ͊̾̈́͘B̢̮̖̊ͧ̃Į̳̘͇̣͖̔͋D̈̑̅͏̟͓̮̰̼̪͈Ď̡̲̠͇͍͓̔E̥̠̱ͫ̋̈̽͢Ņ̹̠̱̮̖̖̝ͣͯ̌ ̠̰̲̗̝̂͞K̶̩̲̖̦̯͕̜̱̃͆ͯ̾Ṉ͔̠̩̗̅̓̈́͢Ǫ̻̳̜̅W̰̩̰̬ͣ͗̕L̽ͦ̂͑҉͇̠E̫͎̝͖͕̰ͣ͡D̖͎͇̔̂ͬ͡G͇͚̩̱̮̹̈́͠E̱̖̯̫̬̫̞͒ͧ͜</summary>

<!-- panvimdoc-ignore-end -->

```fennel
;; plugin.fnl

;; must define as function that returns a list
(fn map-seq-fn [seq f]
  `(icollect [_# v# (ipairs ,seq)] (,f v#)))

(fn call [ast scope ...]
  (match ast
    ;; match against symbol and capture arguments
    [[:map-seq] & other]
    ;; written as do for comment clarity
    (do
      ;; expand our macro as compiler would do, passing in capture arguments
      (local macro-ast (map-seq-fn (unpack other)))
      ;; now expand that ast again (this expands icollect etc, *other* macros)
      (local true-ast (macroexpand macro-ast))
      ;; change ast to match macro ast, note that we must
      ;; **modifiy** the ast, not return a new one, as we're
      ;; actually modifying the ast back in the compiler call-site.
      (each [i ex-ast (ipairs true-ast)]
        (tset ast i ex-ast))))
  ;; nil to continue other plugins
  (values nil))

{:name :magic-map-seq
 :call call
 :versions [:1.2.1]}
```

```fennel
;; file.fnl
(map-seq [1 2 3] #(print $)) ;; works by magic
```

<!-- panvimdoc-ignore-start -->

</details>

<!-- panvimdoc-ignore-end -->
