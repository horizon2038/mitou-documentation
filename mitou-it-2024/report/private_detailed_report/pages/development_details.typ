#import "/components/api_table.typ" : *

= 開発内容

== A9N Microkernelの開発

=== API Primitive

A9N MicrokernelはUserに対してKernel Callを提供する．
Kernel Callは細分化することができ，以下2 + 1個のAPIを提供する．これらは従来型SystemにおけるSystem Callに相当するものである:

+ Capability Call
+ Yield Call
+ Debug Call

従来型のSystem，例えばLinux KernelのSystem Call数は2024年時点で300を超える @LinuxSyscalls:2024 が，A9Nはその1/100程度でSystemを構築することが可能である．

=== Capability Overview

// Capabilityの基礎概念を説明する
A9N Microkernelの実装にはObject-Capability Model @DennisEtAl:1966 によるCapability-Based Securityを採用し，従来のシステムが抱えていた課題を解消した．
Capabilityは特権的リソース : Objectに対するアクセス権限を示すUniqueなTokenである．
従来のACLを用いたアクセス $dash.em.two$ リソース自身がPermissionを確認する方式とは異なり，該当Capabilityの所有者のみが操作を実行可能である．
このように，PoLPを満たしつつも柔軟なアクセス制御を実現する．

言い換えるとCapabilityはTokenであり，間接的にObjectへアクセスするためのHandleである．
要するに，あらゆる特権的操作はObjectが持つ固有機能の呼び出しとしてModel化される．したがって，Object-Oriented ProgrammingにおけるObjectのMethod Callと同等に捉えることができる．
また，CapabilityとObjectを同一視することもできる．よって，この文書ではCapabilityとObjectを同義として扱う．

Capabilityは複数のContext間でCopyやMoveが可能である．この仕組みにより，UserはCapabilityをServer間で委譲して特権的な操作の実行範囲を最小化できる．

=== Capabilityの操作体系

A9N Microkernelにおいて，操作対象のCapabilityを指定するためにCapability Descriptorと呼ばれる符号なし整数型を用いる．
Capability Descriptorは後述するCapability Nodeを再帰的に探索するためのAddressである．
Capability Callの実行時，First ArgumentとしてCapability Descriptorを指定する (@capability_call_pseudo_code) ことでRoot Capability Nodeから対象が暗黙的に探索される．

#v(1em)
#figure(
    ```rust
    fn capability_call(target: capability_descriptor, args ...) -> capability_result
    ```,
    caption: "Capability CallのPseudo Code",
) <capability_call_pseudo_code>
#v(1em)

=== Capability Slot

Capabilityは内部的にCapability Slotと呼ばれるデータ構造に格納される．
Capability SlotはCapability ComponentへのPointerとSlot Local Data，Capability Rights，Dependency Nodeから構成される．

=== Capability Component

すべてのCapabilityをC++上で統一的に扱うため，Capability ComponentというInterface Classを定義する (@capability_component)．
Capability ComponentはGoF @GammaEtAl:1994 におけるCommand PatternとComposite Patternを統合したものであり，Capabilityの実行と初期化，探索を統一的なInterfaceによって提供する.

#v(1em)
#figure(
    ```cpp
    class capability_component
    {
      public:
        // command
        virtual capability_result execute(
            process &owner,
            capability_slot &self
        ) = 0;
        virtual capability_result revoke(capability_slot &self) = 0;

        // composite
        virtual capability_lookup_result retrieve_slot(a9n::word index) = 0;
        virtual capability_lookup_result traverse_slot(
            a9n::capability_descriptor descriptor,
            a9n::word                  descriptor_max_bits,
            a9n::word                  descriptor_used_bits
        ) = 0;
    };
    ```,
    caption: "Capability ComponentのInterface",
) <capability_component>

=== Slot Local Data

SlotにCapability ComponentへのPointerを格納するだけでは問題が生じる．
例えばProcess Control BlockのようなCapabilityを考えると，これはComponentとしてのInstanceごとに状態を持つため問題は発生しない．
しかしながらMemoryに関連するCapability(e.g., Generic, Page Table, Frame)を考えたとき，これらのために1つずつUniqueなInstanceを作成していては効率が悪い．
よって，そのようなUsecaseに対応するためSlot Local Dataを導入した．
対象のCapabilityはSlot Local Dataにそれらの情報を保持し，Capability Componentとして指すInstanceはCapabilityごとに単一のものを共有するようなアプローチを取ることができる．
これにより，Memoryの新規割り当てを必要とせずにCapabilityを作成可能とした．
このSlot Local Dataという仕組みはMemoryに関連するCapabilityに限らず有用であり，どのように利用するかはCapability Componentの実装によって決定される．

=== Capability Rights

前述した通り，一部の例外を除いてCapabilityはCopyやMoveが可能である．
CapabilityがCopyされた場合，DestinationとSourceは同一のCapabilityとして扱われる．

しかし，これらのCapabilityに対して別々のアクセス制御を実行したいUsecaseが存在する．
典型例として，IPC Port Capabilityを親が子に共有するが，子からはこのCapabilityを削除できないようにしたい#footnote()[Dependency Nodeを除いて親や子といった概念はKernelに存在しない．これはKernelを使用するOS Layerでみたときの例である．]場合がある．
このようなシナリオに対応するため，Capability Slot固有のCapability Rightsを導入した．
Capability RightsはCapabilityのCopyやRead，Writeに対する挙動を制御するためのBit Flagである (@capability_rights)．

#v(1em)
#figure(
    ```cpp
    enum object_rights : uint8_t
    {
        NONE   = 0,
        READ   = 1 << 0,
        WRITE  = 1 << 1,
        COPY   = 1 << 2,
        MODIFY = 1 << 3,
        // MOVE is always allowed
        ALL = READ | WRITE | COPY | MODIFY,
    };

    ```,
    caption: "Capability Rightsの定義",
) <capability_rights>
#v(1em)

=== Dependency Node

=== Capability Node

Capability NodeはCapabilityを格納するためのCapabilityである．そのため，Capability NodeにCapability Nodeを格納することも可能である．

=== Generic Capability

Generic Capabilityは物理的なMemoryを抽象化したCapabilityである．
GenericはBase Address, Size Radix Bits, Watermark, そしてDevice Bitsから構成される．

- Base AddressはGenericが指すMemory Regionの開始Physical Addressである．この値はGenericの生存期間中に変化しない．
- Size Radix BitsはGenericが指すMemory RegionのSizeを示す．$2^"size_radix_bits"$が実際のSizeを表す．この事実から分かるように，GenericのSizeは必ず2の累乗byteである．
- WatermarkはGenericの使用状況を示すPhysical Addressである．
- Device BitsはMemory RegionがDeviceのために使用されるような場合(e.g., MMIO)に設定される．Base Addressと同様に，この値はGenericの生存期間中に変化しない．

Generic CapabilityはすべてのCapabilityを作成するためのFactoryとして機能する．
Convert操作 (@generic::convert) によってGeneric Capabilityの領域を消費し，新たなCapabilityを生成することができる．
作成したCapabilityはDependency Nodeに設定され，破棄の再帰的な実行に利用される．

#figure(
    api_table(
        "capability_descriptor", "generic_descriptor", "対象GenericへのDescriptor",
        "capability_type", "type", "作成するCapabilityのType",
        "word", "specific_bits", [Capability作成時に使用する固有Bits \ cf., @generic::specific_bits],
        "word", "count", "作成するCapabilityの個数",
        "capability_descriptor", "node_descriptor", "格納先NodeへのDescriptor",
        "word", "node_index", "格納先NodeのIndex",
    ),
    caption: "generic::convert",
) <generic::convert>

#figure(
    normal_table(
        "Capability Node", [NodeのSlot数を表すRadix ($"count" = 2^"specific_bits"$)],
        "Generic", [GenericのSizeを表すRadix ($"size" = 2^"specific_bits"$)],
        "Process Control Block", "-",
        "IPC Port", "-",
        "Interrupt Port", "-",
        "Page Table", "depth",
        "Frame", "-",
        "Virtual CPU", "-",
        "Virtual Page Table", "-",
    ),
    caption: "generic::specific_bits",
) <generic::specific_bits>


=== Address Space Capability

=== Page Table Capability

=== Frame Capability

=== Process Control Block Capability

=== IPC Port Capability

=== Notification Port Capability

== Interrupt Region Capability

== Interrupt Port Capability

== IO Port Capability

== Virtual CPU Capability

== Virtual Address Space Capability

== Virtual Page Table Capability

== A9N Protocol

=== Boot Protocol

=== Init Protocol

== Nun Operating System Frameworkの開発

=== Custom Target

=== HAL

=== Entry Point

=== API

== KOITOの開発

=== Standard C Library

=== Memory Management Server

=== POSIX Server

== `liba9n`の開発

=== `liba9n::option<T>`

=== `liba9n::result<T, E>`

=== Monadic Operation

=== Conditionally Trivial Special Member Functions

=== `liba9n::not_null<T>`

== A9NLoaderの開発

=== Init ServerのLoad

=== ELF Symbolの解決
