(fn find-ft-plugins [filetype]
  ;; search for hotpot-ftplugin.type via loader then search for
  ;; ftplugin/<filetype>.fnl and compile to cache under
  ;; hotpot-ftplugin/lua/type.lua then load it.
  (let [{: make-searcher : make-ftplugin-record-loader} (require :hotpot.loader)
        {: make-ftplugin-record} (require :hotpot.lang.fennel)
        search-runtime-path (let [{: search} (require :hotpot.searcher)]
                              (fn [modname]
                                (search {:prefix :ftplugin
                                         :extension :fnl
                                         :modnames [(.. filetype)]
                                         ;; TODO :all? true after loader supports returning multiple or extend loader to support paths too and search + loader locally
                                         :package-path? false})))
        searcher (make-searcher)
        modname (.. :hotpot-ftplugin. filetype)
        make-loader #(make-ftplugin-record-loader
                       make-ftplugin-record $1 $2)]
    (case (searcher modname)
      loader (loader)
      nil (case-try
            (search-runtime-path filetype {:prefix :ftplugin}) [path]
            ;; this will move ftplugin/x.fnl in to <namespace>/lua/hotpot-ftplugin/x.lua
            ;; which means the regular loader can find it next time.
            (make-loader modname path) (where loader (= :function (type loader)))
            (loader)))))

(var enabled? false)
(fn enable []
  (let [{: nvim_create_autocmd : nvim_create_augroup} vim.api
        au-group (nvim_create_augroup :hotpot-ftplugin {})
        cb #(do
              (find-ft-plugins (vim.fn.expand "<amatch>"))
              (values nil))]
    (when (not enabled?)
      (set enabled? true)
      (nvim_create_autocmd :FileType {:callback cb :group au-group}))))

(fn disable []
  (when enabled?
    (vim.api.nvim_del_autocmd_by_name :hotpot-ftplugin)))

{: enable : disable}


