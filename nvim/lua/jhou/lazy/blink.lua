return {
    'saghen/blink.cmp',
    version = '1.*',

    opts = {
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
}
