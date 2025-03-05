#import "/components/term.typ" : technical_term
#import "/components/link.typ" : link_with_description

= 付録

== 用語説明

#technical_term(name: "Kernel")[システムとHardwareを接続する中核をなすソフトウェア．]
#technical_term(name: "Monolithic Kernel")[OSにおける多くの機構を内包するKernel．]
#technical_term(name: "Microkernel")[提供する機構を最小化したKernel．]
#technical_term(name: "HAL")[Hardware Abstraction Layerの略称．Kernelから直接Hardwareを呼び出すのではなく，抽象Interfaceによる境界を設定することで移植容易性を高めるための仕組み．]
#technical_term(name: "OS")[Kernelの提供するAPIを用い，要件達成のための機構をUserに提供する\ ソフトウェア．]
#technical_term(name: "IPC")[Inter-Process Communicationの略称であり，あるContextと別のContextが相互に通信することを表す．]
#technical_term(name: "eBPF")[Extended Berkeley Packet Filterの略称．Linux Kernelにおいて，Kernel Spaceで動作するプログラムを実装しKernelの動作を動的に変更するための仕組み．]
#technical_term(name: "Wasm")[WebAssemblyの略称．Portableかつ低レベルなBinary Codeの共通表現を定義したもの．]
#technical_term(name: "TCB")[Trusted Computing Baseの略称であり，Userが信頼しなければならないHardwareやSoftwareの要素を表す．]
#technical_term(name: [PoLP])[Principle of Least Privilegeの略称であり，最小特権の原則 @SaltzerEtAl:1973 ともいう．]
#technical_term(name: [Policy/Mechanism Separation])[機構と方針の分離 @LevinEtAl:1975．ある機構(Mechanism)が提供する機能とそれを利用する方針(Policy)を分離することで，柔軟にシステムの変更を容易にすること．]
#technical_term(name: "Linux")[Linus Torvaldsによって開発されたMonolithic Kernel．]
#technical_term(name: "C++")[Bjarne Stroustrupによって開発されたMulti-Paradigm Programing Language．System Programmingに幅広く使用される．]
#technical_term(name: "Rust")[Mozillaによって開発されたMulti-Paradigm Programing Language．Linear Type SystemによりMemory Safetyを保証するため，CやC++に変わるSystem Programming Languageとして注目されている．]
#technical_term(name: "L4")[Jochen Liedtkeによって開発された，高速なIPC性能を持つ2nd-Generation Microkernel．]
#technical_term(name: "seL4")[NICTAのTrustworthy Systemsによって開発された3rd-Generation Capability-Based Microkernel．]
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

== Sample Codes

=== Nunを用いたHello Worldプログラム <nun::hello_world>

==== `hello-world/src/main.rs`

```rust
#![no_std]
#![no_main]

// using Nun!
use nun;

// configure entry point
nun::entry!(main);

fn main(init_info: &nun::InitInfo) {
    nun::println!("Hello, Nun World!");

    loop {}
}
```

#pagebreak()

=== `liba9n::result<T, E>`を用いたMethod Chain <liba9n::result::example>

==== `src/kernel/process/process_manager.cpp`

#block()[
```cpp 
kernel_result process_manager::switch_to_idle(void)
{
    return a9n::hal::current_local_variable()
        .transform_error(convert_hal_to_kernel_error)
        .and_then(
            [&](cpu_local_variable *local_variable) -> kernel_result
            {
                local_variable->current_process = &idle_process;
                local_variable->is_idle         = true;

                return {};
            }
        );
}
```
]

#show bibliography : set heading(level: 2)
#pagebreak()
#bibliography("/resources/references.bib", title: "参考文献")

