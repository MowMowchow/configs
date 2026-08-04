return {
    'saghen/blink.cmp',
    version = '1.*',

    -- Deferred to the first insert/command-line. Completion cannot be wanted
    -- before then, and lsp.lua's `require("blink.cmp").get_lsp_capabilities()`
    -- pulls it in earlier anyway when a buffer opens -- an explicit require
    -- loads a lazy plugin regardless of its trigger -- so LSP capabilities are
    -- unaffected.
    event = { "InsertEnter", "CmdlineEnter" },

    opts = {
        -- Use Lua fuzzy matching: the prebuilt Rust binary download fails behind
        -- some corporate proxies, and the Lua path needs no network at all
        fuzzy = { implementation = "lua" },

        keymap = {
            preset = 'none',
            ['<CR>'] = { 'accept', 'fallback' },
            ['<Tab>'] = { 'select_next', 'fallback' },
            ['<S-Tab>'] = { 'select_prev', 'fallback' },
        },

        appearance = {
            nerd_font_variant = 'mono',
        },

        sources = {
            default = { 'lsp', 'path', 'buffer' },
        },

        completion = {
            documentation = {
                auto_show = true,
                auto_show_delay_ms = 200,
                window = {
                    border = 'rounded',
                    -- Force right side (east) first
                    direction_priority = {
                        menu_north = { 'e', 'w', 'n', 's' },
                        menu_south = { 'e', 'w', 's', 'n' },
                    },
                },
            },
            menu = {
                border = 'rounded',
            },
        },
    },

    -- Allow site plugins to append their own completion sources
    opts_extend = { "sources.default" },
}
