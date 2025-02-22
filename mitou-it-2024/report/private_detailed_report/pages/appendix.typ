= 付録

== 用語説明

=== Kernel
=== OS 
=== Microkernel

== 関連Webサイト

#let link_with_description(url: "example.com", description: [This is an Example]) = {
    block(width: 100%)[
        #set align(left)
        #link(url)
        #linebreak()
        #h(1em)
        #description
    ]
    v(1em)
}

#link_with_description(url: "https://github.com/horizon2038/A9N", description: "A9N Microkernel")
#link_with_description(url: "https://github.com/horizon2038/A9NLoader", description: "A9N Boot Protocol(x86_64) に従ったReference Bootloader実装")
#link_with_description(url: "https://github.com/horizon2038/Nun", description: "A9N Microkernel上で動作するOSを開発するためのRust製Framework")

#show bibliography : set heading(level: 2)
#bibliography("/resources/references.bib", title: "参考文献")

// == Sample Codes
