local M = {}

function M.require_nui()
    local ok_popup, Popup = pcall(require, "nui.popup")
    local ok_input, Input = pcall(require, "nui.input")
    local ok_autocmd, autocmd = pcall(require, "nui.utils.autocmd")
    if not ok_popup or not ok_input or not ok_autocmd then
        vim.notify("codex.nvim requires nui.nvim", vim.log.levels.ERROR, { title = "codex.nvim" })
        return nil
    end
    return Popup, Input, autocmd.event
end

function M.prepare_buffer(bufnr, filetype)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].filetype = filetype
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modeline = false
    vim.diagnostic.enable(false, { bufnr = bufnr })
end

function M.prepare_input_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.bo[bufnr].filetype = "codex-prompt"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modeline = false
    vim.diagnostic.enable(false, { bufnr = bufnr })
end

function M.prepare_window(winid)
    if not winid or not vim.api.nvim_win_is_valid(winid) then
        return
    end

    vim.wo[winid].spell = false
end

return M
