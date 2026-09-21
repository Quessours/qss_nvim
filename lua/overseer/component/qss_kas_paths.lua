-- Overseer loads components by name from every lua/overseer/component/ on the
-- runtimepath, this one included.
--
-- A kas-container build compiles inside the container, so every path gcc prints
-- is a container path: /build/tmp/work/<machine>/<recipe>/<version>/git/src/foo.cpp.
-- No such file exists here, so the diagnostic would land in an empty buffer of
-- that name. This rewrites the file name of every parsed item to the host path
-- the container had mounted there, and it has to sit before
-- qss_build_diagnostics in the component list, which is the order they run in.

local project = require('qss_nvim.kas.project')

return {
    desc = 'Rewrite container paths in build output to host paths',
    constructor = function()
        return {
            on_result = function(_, task, result)
                if not result.diagnostics then
                    return
                end

                local root = project.root(task.cwd)
                for _, item in ipairs(result.diagnostics) do
                    if item.filename then
                        item.filename = project.to_host(item.filename, root)
                    end
                end
            end,
        }
    end,
}
