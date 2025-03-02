#import "/components/term.typ" : technical_term
#import "/components/link.typ" : link_with_description

= 付録

== 用語説明

#technical_term(name: "Kernel")[システムとHardwareを接続する中核をなすソフトウェア．]
#technical_term(name: "Microkernel")[提供する機構を最小化したKernel．]
#technical_term(name: "HAL")[Hardware Abstraction Layerの略称．]
#technical_term(name: "OS")[Kernelの提供するAPIを用い，要件達成のための機構をUserに提供する\ ソフトウェア．]
#technical_term(name: "TCB")[Trusted Computing Baseの略称であり，Userが信頼しなければならないHardwareやSoftwareの要素を表す．]
#technical_term(name: [PoLP @SaltzerEtAl:1973])[Principle of Least Privilegeの略称であり，最小特権の原則ともいう．]
#technical_term(name: [Policy/Mechanism Separation @LevinEtAl:1975])[機構と方針の分離．ある機構(Mechanism)が提供する機能を，それを利用する方針(Policy)から分離することで，方針の変更を容易にする．]
#technical_term(name: "Linux")[Linus Torvaldsによって開発されたMonolithic Kernel．]
#technical_term(name: "L4")[Jochen Liedtkeによって開発された，高速なIPC性能を持つ2nd-Generation Microkernel．]
#technical_term(name: "seL4")[Trustworthy Systemsによって開発された3rd-Generation Capability-Based Microkernel．]
#technical_term(name: "Fiasco.OC")[L4系列の3rd-Generation Capability-Based Microkernel．]
#technical_term(name: "Zircon")[Googleによって開発された3rd-Generation Microkernel．]
#technical_term(name: "UEFI")[Unified Extensible Firmware Interfaceの略称であり，OSとPlatform間のInterfaceを定義する規格．]
#technical_term(name: "EDK2")[
    TianoCore Projectによって開発されているUEFI Applicationの開発環境．また，UEFI仕様のReference Implementation．
]

== 関連Webサイト

#link_with_description(url: "https://github.com/horizon2038/A9N", description: "A9N Microkernel")
#link_with_description(url: "https://github.com/horizon2038/A9NLoader", description: "A9N Boot Protocol(x86_64) に従ったReference Bootloader実装")
#link_with_description(url: "https://github.com/horizon2038/Nun", description: "A9N Microkernel上で動作するOSを開発するためのRust製Framework")

#show bibliography : set heading(level: 2)
#pagebreak()
#bibliography("/resources/references.bib", title: "参考文献")

// == Sample Codes
