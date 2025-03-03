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

=== `liba9n::result<T, E>`を用いたMethod ChainによるError Handling <liba9n::result::example>

==== `src/kernel/process/process_manager.cpp`

#block()[
```cpp 
kernel_result process_manager::try_schedule_and_switch(void)
{
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

}
```
]

#show bibliography : set heading(level: 2)
#pagebreak()
#bibliography("/resources/references.bib", title: "参考文献")

