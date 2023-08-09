import { defineConfig } from "vitepress"

// https://vitepress.dev/reference/site-config
export default defineConfig({
    title: "ECR",
    description: "A Luau ECS library.",
    base: "/ecr/",
    head: [["link", { rel: "icon", href: "/logo.svg" }]],
    ignoreDeadLinks: true,

    themeConfig: {
        logo: "/logo.svg",

        // https://vitepress.dev/reference/default-theme-config
        nav: [
            { text: "Home", link: "/" },
            { text: "Tutorials", link: "/tut/crashcourse" },
            { text: "API", link: "/api/ecr"},
            { text: "GitHub", link: "https://github.com/centau/ecr" }
        ],

        outline: "deep",

        sidebar: {
            "/api/": [
                {
                    text: "API",
                    items: [
                        { text: "ecr", link: "/api/ecr" },
                        { text: "Registry", link: "/api/Registry" },
                        { text: "View", link: "/api/View" },
                        { text: "Observer", link: "/api/Observer" },
                        { text: "Group", link: "/api/Group" },
                        { text: "Handle", link: "/api/Handle" },
                        { text: "Signal", link: "/api/Signal" },
                        { text: "Queue", link: "/api/Queue" },
                        { text: "Pool", link: "/api/Pool" },
                        { text: "Restrictions", link: "/api/restrictions" },
                    ]
                }
            ],

            "/tut/": [
                {
                    text: "Tutorials",
                    items: [
                        { text: "Crash Course", link: "/tut/crashcourse" },
                        { text: "Groups", link: "/tut/groups" },
                    ]
                }
            ],
        }

        // socialLinks: [
        //     { icon: "github", link: "https://github.com/centau/vide" }
        // ]
    }
})
