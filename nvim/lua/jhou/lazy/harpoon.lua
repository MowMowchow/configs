return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = {
        "nvim-lua/plenary.nvim"
    },

    config = function()
        local harpoon = require("harpoon")

        -- Setup with custom recency list
        harpoon:setup({
            recency = {
                select = function(list_item)
                    if list_item then
                        vim.cmd("edit " .. list_item.value)
                    end
                end,
            },
        })

        -- Main harpoon keymaps
        vim.keymap.set("n", "<leader>ha", function() harpoon:list():add() end)
        vim.keymap.set("n", "<leader>hl", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

        -- vim.keymap.set("n", "<C-h>", function() harpoon:list():select(1) end)
        -- vim.keymap.set("n", "<C-t>", function() harpoon:list():select(2) end)
        -- vim.keymap.set("n", "<C-n>", function() harpoon:list():select(3) end)
        -- vim.keymap.set("n", "<C-s>", function() harpoon:list():select(4) end)

        -- Toggle previous & next buffers stored within Harpoon list
        vim.keymap.set("n", "<C-p>", function() harpoon:list():prev() end)
        vim.keymap.set("n", "<C-n>", function() harpoon:list():next() end)

        -- Recency list: shows recently visited files
        vim.keymap.set("n", "<leader>hr", function()
            local recency = require("jhou.recency")
            local recency_list = harpoon:list("recency")

            -- Clear and rebuild from tracked visits
            recency_list._length = 0
            recency_list.items = {}

            for _, entry in ipairs(recency.get_sorted()) do
                recency_list:add({ value = entry.value, context = { row = 1, col = 0 } })
            end

            harpoon.ui:toggle_quick_menu(recency_list)
        end)
    end
}
