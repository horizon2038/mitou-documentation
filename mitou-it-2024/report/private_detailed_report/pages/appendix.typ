= 付録

== 用語説明

#let term(description, name: [Example]) = context {
    block(width: 100%)[
        #set align(left)
        *#name*
        #linebreak()
        #pad(left: 1em)[
            #description
        ]
    ]
    v(0.5em)
}

#term(name: "Kernel")[システムとHardwareを接続する中核をなすソフトウェア．]
#term(name: "OS")[Kernelの提供するAPIを用い，要件達成のための機構をUserに提供する\ ソフトウェア．]
#term(name: "TCB")[Trusted Computing Baseの略称であり，Userが信頼しなければならないHardwareやSoftwareの要素を表す．]
#term(name: "Microkernel")[提供する機構を最小化したIPC-BasedなKernel．]
#term(name: "PoLP")[Principle of Least Privilegeの略称であり，最小特権の原則ともいう．]
#term(name: "L4")[Jochen Liedtkeによって開発された，高速なIPC性能を持つMicrokernel．]
#term(name: "seL4")[Trustworthy Systemsによって開発されたCapability-Based Microkernel．]
#term(name: "Zircon")[Googleによって開発されたCapability-Based Microkernel．]
#term(name: "UEFI")[Unified Extensible Firmware Interfaceの略称であり，OSとPlatform間のInterfaceを定義する規格．]
#term(name: "EDK2")[
    TianoCore Projectによって開発されているUEFI Applicationの開発環境．また，UEFI仕様のReference Implementation．
]

== 関連Webサイト

#let link_with_description(url: "example.com", description: [This is an Example]) = {
    block(width: 100%)[
        #set align(left)
        #link(url)
        #linebreak()
        #pad(left: 1em)[
            #description
        ]
    ]
    v(0.5em)
}

#link_with_description(url: "https://github.com/horizon2038/A9N", description: "A9N Microkernel")
#link_with_description(url: "https://github.com/horizon2038/A9NLoader", description: "A9N Boot Protocol(x86_64) に従ったReference Bootloader実装")
#link_with_description(url: "https://github.com/horizon2038/Nun", description: "A9N Microkernel上で動作するOSを開発するためのRust製Framework")

#show bibliography : set heading(level: 2)
#pagebreak()
#bibliography("/resources/references.bib", title: "参考文献")

// == Sample Codes
