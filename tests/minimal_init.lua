vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nui.nvim")

require("codex").setup({})
