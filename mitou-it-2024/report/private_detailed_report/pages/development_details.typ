#import "/components/api_table.typ" : *
#import "@preview/bytefield:0.0.7": *
#import "@preview/cetz:0.3.2"

#import "/components/term.typ" : *

= 開発内容

/* ===== A9N ===== */

== A9N Microkernelの開発

=== History of A9N Microkernel

=== Basic Types

A9N MicrokernelはC++20を用いて開発されているが，Kernel内部で広範に使用するための基本型を定義している．
Kernel内部では幅が固定された型を基本的に使用せずに`word`型を使用する．
`word`はArchitecture-SpecificなWord幅を持つ符号なし整数型であり，`uintmax_t`や`usize`のAliasとして定義される．
これにより，速度と移植容易性を実現する．

A9NにおけるKernelの呼び出し機構はC ABIに依存しないVirtual Message Register-Basedなものである．
したがって，Kernelは多値の返却や正常値とエラー値の区別が可能な形式でUserに制御を返すことができる．
そのため，言語のLibraryレベルでMapperを作成することにより，NativeなResult型やその他の型を返すことができる．
このようなAPIのRustによるReference ImplementationはNun OS Frameworkに内包されている．

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

#figure(
    ```rust
    fn capability_call(target: capability_descriptor, args ...) -> capability_result
    ```,
    caption: "Capability CallのPseudo Code",
) <capability_call_pseudo_code>

=== Capability Slot

Capabilityは内部的にCapability Slotと呼ばれるデータ構造に格納される．
Capability SlotはCapability ComponentへのPointerとSlot Local Data，Capability Rights，Dependency Nodeから構成される．

==== Capability Component

すべてのCapabilityをC++上で統一的に扱うため，Capability ComponentというInterface Classを定義する (@capability_component)．
Capability ComponentはGoF @GammaEtAl:1994 におけるCommand PatternとComposite Patternを統合したものであり，Capabilityの実行と初期化，探索を統一的なInterfaceによって提供する.

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

すべてのCapabilityはCapability Componentの実装である．

==== Slot Local Data

SlotにCapability ComponentへのPointerを格納するだけでは問題が生じる．
例えばProcess Control BlockのようなCapabilityを考えると，これはComponentとしてのInstanceごとに状態を持つため問題は発生しない．
しかしながらMemoryに関連するCapability(e.g., Generic, Page Table, Frame)を考えたとき，これらのために1つずつUniqueなInstanceを作成していては効率が悪い．
よって，そのようなUsecaseに対応するためSlot Local Dataを導入した．
対象のCapabilityはSlot Local Dataにそれらの情報を保持し，Capability Componentとして指すInstanceはCapabilityごとに単一のものを共有するようなアプローチを取ることができる．
これにより，Memoryの新規Allocationを必要とせずにCapabilityを作成可能とした．
このSlot Local Dataという仕組みはMemoryに関連するCapabilityに限らず有用であり，どのように利用するかはCapability Componentの実装によって決定される．

==== Capability Rights

前述した通り，一部の例外を除いてCapabilityはCopyやMoveが可能である．
CapabilityがCopyされた場合，DestinationとSourceは同一のCapabilityとして扱われる．

しかし，これらのCapabilityに対して別々のアクセス制御を実行したいUsecaseが存在する．
典型例として，IPC Port Capabilityを親が子に共有するが，子からはこのCapabilityを削除できないようにしたい#footnote()[Dependency Nodeを除いて親や子といった概念はKernelに存在しない．これはKernelを使用するOS Layerでみたときの例である．]場合がある．
このようなシナリオに対応するため，Capability Slot固有のCapability Rightsを導入した．
Capability RightsはCapabilityのCopyやRead，Writeに対する挙動を制御するためのBit Flagである (@capability_rights)．

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

Capability Rightsには，先天的に設定されるものと後天的に設定するものの両方が存在する．
原則として，Capabilityは作成時点にすべてのRights Bitが設定される．
ただし，Copyを許可すると同一性が失われてしまうようなCapabilityはCopyが最初から禁止される．

==== Dependency Node

Capabilityはその依存関係をDependency Node (@dependency_node) によって管理する．
Dependency Nodeは依存関係にあるCapability Slotを保持するが，`depth`によって子と兄弟を区別する．

#figure(
    ```cpp
    struct capability_slot
    {
        // 前略
        capability_slot     *next_slot;
        capability_slot     *preview_slot;
        a9n::word depth;
        // 後略
    };
    ```,
    caption: "Capability SlotのDependency Node部",
) <dependency_node>

- 親の区別は可能だが，通常使用されないため省略される．
- `next_slot`もしくは`preview_slot`の`depth`が自分自身の`depth`と等しい場合，そのSlotは兄弟である．
- `next_slot`の`depth`が自分自身の`depth`よりも大きい場合そのSlotは子である．子は必ず`next_slot`側に設定されるため，`preview_slot`の`depth`は比較しない．

Dependency Nodeは所有関係を表すものではなく，あくまでも派生と同一性を表すために利用される．

#pagebreak()

=== Virtual Message Register

A9N MicrokernelではCapability CallのためにVirtual Message Register#footnote[L4 Microkernel FamilyにおけるUTCBと同等]機構を使用する．
Virtual Message Registerはその名の通り，Communicationに使用するためのMessageを格納するRegisterである．

- ArchitectureごとにVirtual Message RegisterはHardware RegisterへMapされる#footnote()[ABI項を参照]．
- Hardware RegisterにMapできないMessage#footnote()[ABI項を参照]はProcess Control BlockごとのIPC Bufferに格納される．IPC BufferはKernelとUser間のShared Memoryであり，必ず存在が保証される．

このアプローチは高速かつSecureなCapability Callを実現する．

- Hardware RegisterへのAccessは一般に高速であるため，Message CopyのOverheadを最小限に抑えることができる．
- IPC BufferはCapabilityによって存在が保証されるため，Kernel SpaceにおけるUser Space起因のPage Faultは発生しない．

=== Scheduler

A9N MicrokernelはBenno Scheduler @ElphinstoneEtAl:2013 をProcess Schedulingに使用する．
Benno Schedulerは従来のSchedulerとは異なり，必ず実行可能なProcessのみをQueueに保持する．
このアプローチはQueue操作を簡易化し，なおかつHot-Cache内で実行されやすくなり高速化される．
その結果としてSystem全体の応答速度は向上する．

=== Kernel-Level Stack

A9N MicrokernelはEvent Kernel Architectureであり，Kernel StackをCPUコアごとに割り当てるSingle Kernel Stack @Warton:2005 アプローチを採用している．
従来のProcess Kernel Architectureでは実行可能なContextごとに4-8KiBのKernel Stackを割り当てていたが，この方式では大量のKernel Memoryを消費してしまう欠点がある．
CPUコアごとのKernel StackはMemory Footprintを削減し，実行可能Context数のScalabilityを向上させる．

// TODO: いい感じの図を作る

#pagebreak()

=== Capability Callの略式表記

本文書では各CapabilityごとのCapability Callを略式表記する．
通常，Capability Call全てに共通な引数は以下のようになる：

#api_table(
    "message_register[0]", "target_descriptor", "対象CapabilityへのDescriptor",
    "message_register[1]", "operation", "対象Capabilityに対する操作",
)

また，返り値は以下のようになる：

#api_table(
    "message_register[0]", "is_success", "操作の成否",
    "message_register[1]", "error", [Capability CallのError#footnote()[現在は簡易化のためにCapability Error型のみを返しているが，将来的にこのFieldもCapability-Definedな値の返却に使用する予定である．]],
)

このようにMessage RegisterのIndex : 0とIndex : 1は予約されているが，統合されCapability Result型として使用される．
それ以外のMessage RegisterはそれぞれのCapabilityが定義したように使用できる．

したがって，各Capability Callの略式表記は以下のようになる：
- 返り値がCapability Result型のみの場合，返り値の表記は省略する．返り値が存在する場合はそれを記述するが，Capability Resultは省略する．
- `operation`はそれぞれのCapability Callによって異なるため，その指定をLibrary Functionに内包させる．そのため，表記からは省略する．

#pagebreak()

=== Capability Node

Capability NodeはCapabilityを格納するためのCapabilityであり，seL4 MicrokernelにおけるCNodeの設計をベースとしている．
1つのNodeは$2^"RadixBits"$個のCapability Slotを持ち．この数だけCapabilityを格納できる．
したがって，論理的にはCapability NodeをCapability Slotの配列としてみなすことができる．

Capability Nodeは効率のためにRadix Page Tableをベースとした木構造を取る．
仮に単純なLinked ListとしてCapability Nodeを実装した場合，Capability Slotの探索には$O(n)$のコストが発生する．
一方，Radix Page Tableをベースとした実装を採用することで，Capability Slotの探索を$O(log n)$で実現することができる．

Capability Componentは`retrieve_slot`と`traverse_slot`を定義するが，この具象となる実装を呼び出すことでCapability Nodeを探索し，対象のCapability Slotを取得することができる．

==== `capability_node::retrieve_slot`#footnote()[`capability_component::retrieve_slot`の実装]
`retrieve_slot`は引数に指定されたIndexに対応するSlotを返す．これは単なる配列アクセスに等しい．

==== `capability_node::traverse_slot`#footnote()[`capability_component::traverse_slot`の実装]
`traverse_slot`Node間の再帰的な探索であり，以下のように実装される:
+ Capability DescirptorからDescriptor Used Bits分をSkipした箇所からNodeのRadix Bits分を取り出し (@calculate_capability_index) ，Node Indexとする．
+ Node Indexを用いてSlotを取得し，次の探査対象とする．
+ 3で取得したSlotからCapability Componentを取得し，再帰的に`taverse_slot`を呼び出す．

#figure(
    ```cpp
inline const a9n::word capability_node::calculate_capability_index(
    a9n::capability_descriptor descriptor,
    a9n::word                  descriptor_used_bits
)
{
    // index用のmask baseを計算する．
    auto mask_bits  = static_cast<a9n::word>((1 << radix_bits) - 1);
    // descriptorからradix bitsを取り出すためのshift bitsを計算する．
    // このshift bitsはdescriptorから未使用bitを取り出すために使用する;
    // 要するに使用済みbitをskipする．
    auto shift_bits = (a9n::WORD_BITS -
        (ignore_bits + radix_bits + descriptor_used_bits)
    );
    // 未使用bitの先頭からradix bitsを取り出しindexとする．
    return (descriptor >> shift_bits) & mask_bits;
}
    ```,
    caption: "Node Indexの取得",
) <calculate_capability_index>

Node以外のCapability Component実装は，`retrieve_slot`や`traverse_slot`の呼び出し時に`capability_lookup_error::TERMINAL`を返す．この機構により，どのCapability Componentを呼び出すかに関わらずCapability Nodeの探索を行うことができる．

==== Addressing

Capability Callの実行時，対象となるCapabilityは指定されたCapability Descriptorを用いて暗黙のうちにRoot Capability Nodeから探索される．
Userが指定したCapability Descriptorの先頭8bitはDepth Bitsであり (@capability_descriptor)，Capability Nodeの探索上限を示す．

#figure(
    bytefield(
        bpr: 64,
        rows: (4em),
        bitheader(
            "offsets",
            0,
            8,
            text-size: 8pt,
        ),

        bits(8)[DEPTH],
        bits(56)[CAPABILITY DESCRIPTOR],

        text-size: 4pt,
    ),
    caption: [Userが指定するCapability Descriptorの構造#footnote()[簡略化のために64bit ArchitectureにおけるDescriptorを例示しているが，異なるWord幅のArchitectureにおいても同様の構造をとる．]],
) <capability_descriptor>

Addressing機構は先述したようにRadix Page Tableをベースとしているが，具体例を示すことで理解の助けとする．

まず，$"Node"_0("Root Node")$, $"Node"_1$, $"Node"_2$のCapability Nodeが存在するとする．
$"Node"_0$のSlot数を$256(i.e., "0xff")$個とした場合，$"Node"_0$の$"Radix Bits"$は
$ log_2(256) = 8 $
となる．

続いて，$"Node"_1$のSlot数を$1024(i.e., "0x400")$個とした場合，$"Node"_1$の$"Radix Bits"$は
$ log_2(1024) = 10 $
となる．

同様に，$"Node"_2$のSlot数を$64(i.e., "0x40")$個とした場合，$"Node"_2$の$"Radix Bits"$は
$ log_2(64) = 6 $
となる．

そして，$"Node"_0$のIndex : $"0x02"$に$"Node"_1$を格納し，$"Node"_1$のIndex : $"0x03"$に$"Node"_2$を格納する．
また，$"Node"_2$のIndex : $"0x04"$にNodeではない終端のCapabilityとして$"Capability"_"Target"$を格納する．

これを図示すると (@capability_node_example) になる．

#figure([
    #cetz.canvas({
        import cetz.draw: *  // Import necessary drawing functions
        group(name: "addressing", {
            // 1. configure style
            set-style(
              stroke: 0.4pt,
              grid: (
                stroke: gray + 0.2pt,
                step: 1
              ),
              mark: (
                transform-shape: false,
                fill: black
              ),
            )

            // 2. configure scale
            scale(2)

            // draw address box
            let box_width = 6
            let box_width_half = box_width / 2
            let box_height = 0.5 
            let box_height_half = box_height / 2
            let padding = 0.2

            // range: 0 ~ 5 => -3 ~ 3
            let calculate_pos_x(x) = {
                return x - box_width_half
            }

            rect((-box_width_half, 0), (box_width_half, -box_height), name: "address_box")
            // content((calculate_pos_x(0) - padding, -box_height_half), "", anchor: "east")

            for (i, descriptor_index, radix) in (
                (0, "0x02", 0x08),
                (1, "0x03", 0x0a),
                (2, "0x04", 0x06),
            ) {
                // draw address descriptor
                let x = calculate_pos_x(i * 2)
                line((x, 0), (x, -box_height))
                content((x + 1, -box_height_half), [#descriptor_index (Radix: #str(radix))], anchor: "center")

                let x_l = (calculate_pos_x(i * 2) + 1) - (padding + 0.25)
                let x_r = (calculate_pos_x(i * 2) + 1) + (padding + 0.25)
                let y_u = -(box_height + padding)
                let y_d = -(box_height + 2)

                rect((x_l, y_u), (x_r, y_d), anchor: "center")

                // draw rows
                for j in range(5) {
                    let step = (y_u - y_d) / 5
                    line((x_l, y_u - (step * j)), (x_r, y_u - (step * j)))

                    if (j == 3) {
                        rect((x_l, y_u - (step * j)), (x_r, y_u - (step * (j + 1))), fill: luma(240))
                        let x_m = (x_l + x_r) / 2
                        let y_m = ((y_u - (step * j)) + (y_u - (step * j + 0.25 + 0.03))) / 2
                        content((x_m, y_m - 0.03), str(descriptor_index), anchor: "center")

                        // draw lines:
                        let next_x_l = (calculate_pos_x((i + 1) * 2) + 1) - (padding + 0.25)

                        // 1. draw line to target index
                        line((x + 0.25, -0.5), (x + 0.25, y_m), (x_l, y_m), mark: (end: ">"))

                        if (i >= 2) {
                            continue
                        }

                        // 2. draw line to next node
                        line((x_r, y_m), (x_r + 0.3, y_m), (x_r + 0.3, y_m + 1), (next_x_l, y_m + 1), mark: (end: ">"))
                    }
                }

                // draw node label
                let x_m = (x_l + x_r) / 2
                content((x_m, y_d - 0.2), [$"Node"_#i$ (Size = $2^#radix$)], anchor: "center")
            }
        })
    })
    ],
    caption: "Capability構成の例"
) <capability_node_example>

ここで, $"Capability"_"Target"$を対象としてCapability Callを実行したい場合を考えると，Capability Descriptorは (@capability_target_descriptor) のようになる#footnote()[簡略化のために32bit ArchitectureにおけるDescriptorを例示しているが，異なるWord幅のArchitectureにおいても同様の構造をとる．]:

//   0001 1000 = 0x24 (depth)
//   0000 0011 = 0x02 (node_0)
// 000000 0011 = 0x03 (node_1)
//     00 0101 = 0x04 (node_2)
#text()[$
    "capability_descriptor"        &:= &"0x"&"180300C5" &("hex") \ 
                        &:= &"0b"&"00011000000000110000000011000101" &("bin")
$] <capability_target_descriptor>
// 00011000'00000011'00000000'11000101

これをNodeのRadix Bitsによってパースすると，(@parsed_capability_target_descriptor) となる:

$
    0b
    overbracket(underbracket(00011000, "Depth"), "8bit")
    overbracket(underbracket(00000011, "Index"_("Node"_0)), "8bit")
    overbracket(underbracket(0000000011, "Index"_("Node"_1)), "10bit")
    overbracket(underbracket(000101, "Index"_("Node"_2)), "6bit")
$ <parsed_capability_target_descriptor>

まず，先頭8bitからDepth Bitsが取り出される．この場合は$"0b00011000" = "0x24"$となる．
Depth Bitsの妥当性を示すため，実際に計算を行う．

$"Capability"_"Target"$に対応するDepth Bitsは (@capability_target_calculated_depth)のように計算される：

$
    "Depth"("Capability"_"Target") &= "Radix"("Node"_0) + "Radix"("Node"_1) + "Radix"("Node"_2) \ 
    &= 8 + 10 + 6 = 24
$ <capability_target_calculated_depth>

ただし，$"Capability"_"Target"$のように終端まで探索を行う場合，Depth Bitsはその最大値を用いることができる (@capability_max_depth)：
$
    "Depth"_"Max" = "WordWidth" - 8
$ <capability_max_depth>

続いて，$"Node"_0$を探索するためのIndexを取得する．$"Node"_0$のRadix Bitsより8bitを取り出し，取得した$"0x02"$を$"Index"_("Node"_0)$とする．
これを用いて$"Node"_0$から$"Node"_1$を得る．

次に，$"Node_1"$を探索するためのIndexを取得する．$"Node_1"$のRadix Bitsより8bitを取り出し，取得した$"0x03"$を$"Index"_("Node"_1)$とする．
これも同様に$"Node_1"$のIndexとし，$"Node_2"$を得る．

最後に，$"Node_2"$を探索するためのIndexを取得する．$"Node_2"$のRadix Bitsより8bitを取り出し，取得した$"0x04"$を$"Index"_("Node_2")$とする．
これにより，最終的な$"Capability"_"Target"$が取得される．

次の例として，$"Node"_1$を対象にCapability Callを実行したい場合を考えると，Capability Descriptorは (@capability_node_1_descriptor) のようになる:

#text()[$
    "capability_descriptor"        &:= &"0x"&"803xxxx" &("hex") \ 
                        &:= &"0b"&"0000100000000011 xxxxxxxxxxxxxxxx" &("bin")
$] <capability_node_1_descriptor>

これをNodeのRadix Bitsによってパースすると，(@parsed_node_1_descriptor) となる:

$
    0b
    overbracket(underbracket(00001000, "Depth"), "8bit")
    overbracket(underbracket(00000011, "Index"_("Node"_0)), "8bit")
    overbracket(underbracket("XXXXXXXXXXXXXXXX", "Unused"), "Remain Bits")
$ <parsed_node_1_descriptor>

これも同様にDepth Bitsの妥当性を検証する．
この場合，Depth Bitsは (@capability_node_1_depth)のように計算される：

$
    "Depth"("Capability"_"Target") &= "Radix"("Node"_0) \ 
    &= 8
$ <capability_node_1_depth>

Depth BitsはNodeのような非終端のCapabilityを指定するために使用される．常に最大値を使用した場合，必ず終端まで探索されてしまうためである．
$"Capability"_"Target"$の探索と途中までは同様であるが，パース済みのDescriptorがDepth Bits以上になった時点で探索を終了する．

==== Capability Call

#technical_term(name: `copy`)[CapabilityのCopyを実行する．RightsはそのままCopyされる．]

#figure(
    api_table(
        "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
        "word", "destination_index", "DestinationとなるCapabilityを格納しているNode内Index",
        "capability_descriptor", "source_descriptor", "SourceとなるNodeのDescriptor",
        "word", "source_index", "SourceとなるNodeのCapabilityを格納しているIndex",
    ),
    caption: "capability_node::copy",
) <capability_node_copy>

#technical_term(name: `move`)[CapabilityのMoveを実行する．RightsはそのままMoveされる．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "destination_index", "DestinationとなるCapabilityを格納しているNode内Index",
    "capability_descriptor", "source_descriptor", "SourceとなるNodeのDescriptor",
    "word", "source_index", "SourceとなるNodeのCapabilityを格納しているIndex",
)

#technical_term(name: `mint`)[CapabilityのMintを実行する．新しいRightsは元となるRightsのSubsetである必要がある．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "destination_index", "DestinationとなるCapabilityを格納しているNode内Index",
    "capability_descriptor", "source_descriptor", "SourceとなるNodeのDescriptor",
    "word", "source_index", "SourceとなるNodeのCapabilityを格納しているIndex",
    "capability_rights", "new_rights", "新しいRights",
)

#technical_term(name: `demote`)[Capability Rightsを不可逆的に降格する．新しいRightsは元となるRightsのSubsetである必要がある．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "target_index", "対象のCapabilityを格納しているNode内Index",
    "capability_rights", "new_rights", "新しいRights",
)

#technical_term(name: `remove`)[CapabilityをSlotから削除する．Dependency Nodeに兄弟が存在しない場合，Revokeを実行してから削除する．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "target_index", "削除対象のCapabilityを格納しているNode内Index"
)

#technical_term(name: `revoke`)[Capabilityを初期化/無効化する．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "target_index", "削除対象のCapabilityを格納しているNode内Index"
)


#pagebreak()

=== Generic Capability

Generic Capabilityは物理的なMemoryを抽象化したCapabilityである．
GenericはBase Address，Size Radix Bits，Watermark，そしてDevice Bitsから構成される．

- Base AddressはGenericが指すMemory Regionの開始Physical Addressである．
- Size Radix BitsはGenericが指すMemory RegionのSizeを示すRadixであり，$2^"SizeRadixBits"$が実際のSizeである．この事実から分かるように，GenericのSizeは必ず2の累乗byteである．
- WatermarkはGenericの使用状況を示すPhysical Addressである．
- Device BitsはMemory RegionがDeviceのために使用されるような場合(e.g., MMIO)に設定される．

Generic CapabilityはすべてのCapabilityを作成するためのFactoryとして機能する．
Convert操作 によってGeneric Capabilityの領域を消費し，新たなCapabilityを生成することができる．
作成したCapabilityはDependency Nodeへ子として設定され，破棄の再帰的な実行に利用される．

==== $log_2$ Based Allocation

GenericのConvert操作時，次のステップでCapabilityを作成する：

+ Convert操作によって指定されたCapability TypeとSpecific BitsからSize Radixを得る．
+ Size Radix分をAllocate可能か確認する．
+ WatermarkをSize RadixにAlign(Ceil)し，WatermarkにSize Radix分を加算する．

#v(1em)

まず，引数として与えられたCapability TypeとSpecific BitsからSize Radixを取得する．
Capability ObjectのSizeを最も近い2の累乗に切り上げ, 2を底とする対数をとる (@calculate_radix_ceil)．

#figure(
    $ "SizeRadix" = ceil.l log_2("Sizeof"("Object")) ceil.r $,
    caption: "Size Radixの計算"
) <calculate_radix_ceil>

Specific Bitsが必要となる理由は，Specific Bitsによって全体としてのSizeが決定されるCapability NodeのようなCapabilityが存在するためである．

次に，Size Radix分のMemory領域がAllocate可能か確認する．Allocateした場合のWatermarkを計算し (@calculate_new_watermark) ，

#figure(
    $
        "NewWatermark" = "SizeRadix" dot stretch(ceil.l, size: #150%) frac("Watermark", "SizeRadix") stretch(ceil.r, size: #150%)
    $,
    caption: "Size RadixにAlignされたWatermarkを計算"
) <calculate_new_watermark>

それが範囲内か確認する (@check_new_boundary)．

#figure(
    $
        "NewWatermark" < "Watermark" + 2^"RadixBits" and \ 
        "NewWatermark" + 2^"SizeRadix" * "Count" <= "BaseAddress" + 2^"RadixBits"
    $,
    caption: "Allocationのための境界チェック"
) <check_new_boundary>

そして，最後にAllocateを実行する．

このように，すべてのCapabilityはAllocate時にAlignされる．そのため，Genericを適切に分割してからCapabilityをConvertすることで自然と*SLAB Allocator*のような振る舞いを実現する#footnote[あるCapabilityのConvertによってAlignが発生すると，次の同一CapabilityをConvertする際に隙間なくAllocateできるため．]．

==== Deallocation

Genericの再利用には，ConvertされたすべてのCapabilityをRemoveする必要がある．
これはGenericに対してRevokeを実行することで再帰的に行われる．
すなわち，ある$"Capability"_"A"$をConvertしたあとに$"Capability"_"B"$をConvertし，$"Capability"_"A"$をRemoveしても$"Capability"_"A"$が使用していた領域を再利用できない．
これはGenericの構造を考えれば明らかである．Genericは単純化と高速化のために単一のWatermarkのみで使用量管理を実現している．したがって，高粒度な再利用をKernelは提供しない．
その実現には，Genericから再利用単位ごとに子となるようなGenericを作成する必要がある#footnote[この実装は完全にUser-Levelで実現される．]．

==== Capability Call

#technical_term(name: `convert`)[Generic Capabilityの領域を指定されたCapability Typeに変換する．]

#api_table(
    "capability_descriptor", "generic_descriptor", "対象GenericへのDescriptor",
    "capability_type", "type", "作成するCapabilityのType",
    "word", "specific_bits", [Capability作成時に使用する固有Bits \ cf., @generic::specific_bits],
    "word", "count", "作成するCapabilityの個数",
    "capability_descriptor", "node_descriptor", "格納先NodeへのDescriptor",
    "word", "node_index", "格納先NodeのIndex",
)

Specific BitsはCapability Type依存の初期化に使用する値である．例えば，Capability NodeをConvertする時に指定するSpecific BitsはNodeのRadixとなる．

#figure(
    normal_table(
        "Capability Node", [NodeのSlot数を表すRadix ($"count" = 2^"specific_bits"$)],
        "Generic", [GenericのSizeを表すRadix ($"size" = 2^"specific_bits"$)],
        "Address Space", "-",
        "Page Table", "depth",
        "Frame", "-",
        "Process Control Block", "-",
        "IPC Port", "-",
        "Notification Port", "-",
        "Interrupt Region", "-",
        "Interrupt Port", "-",
        "Virtual CPU", "-",
        "Virtual Address Space", "-",
        "Virtual Page Table", "-",
    ),
    caption: "generic::specific_bits",
) <generic::specific_bits>

#pagebreak()

=== Address Space Capability

Address Space CapabiltyはVirtual Address Spaceを抽象化したCapabilityである．すべての実行可能なContextはAddress Space Capabilityを持ち，Context Switch時に切り替えることでAddress Spaceを切り替える．
異なる2つのProcess Control Blockに同一のAddress Space Capabilityを設定することで，同一のVirtual Address Spaceを共有し，いわゆるThreadをUser-Levelで実現することができる．

Address Space CapabilityにはPage Table CapabilityやFrame CapabilityをMapping可能である．これにより，User-LevelでVirtual Memory Managementを実現することができる．

==== Capability Call

#technical_term(name: `map`)[Page TableやFrameをVirtual Address SpaceにMapする．]

#api_table(
    "capability_descriptor", "memory_descriptor", "対象Address SpaceへのDescriptor",
    "capability_descriptor", "target_descriptor", "対象にMapするPage TableもしくはFrameへのDescriptor",
    "virtual_address", "address", "Mapする仮想アドレス",
    "memory_attribute", "attribute", "Mapに使用する属性",
)

#technical_term(name: `unmap`)[Page TableやFrameをVirtual Address SpaceからUnmapする．]

#api_table(
    "capability_descriptor", "page_table_descriptor", "対象Address SpaceへのDescriptor",
    "capability_descriptor", "target_descriptor", "対象からUnmapするPage TableもしくはFrameへのDescriptor",
    "virtual_address", "address", "Unmapする仮想アドレス",
)

#technical_term(name: `get_unset_depth`)[Address Spaceに仮想アドレスをMapするうえで，まだMapされていないPage TableのDepthを取得する．]

#figure(
    api_table(
        "capability_descriptor", "memory_descriptor", "対象Address SpaceへのDescriptor"
    ),
    caption: [`get_unset_depth`の引数]
)

#figure(
    api_table(
        "word", "depth", "MapされていないPage TableのDepth"
    ),
    caption: [`get_unset_depth`の返り値]
)

#pagebreak()

=== Page Table Capability

Page Table CapabilityはPage Tableをそのまま抽象化したCapabilityである．
Page Table CapabilityはAddress Space CapabilityにMap可能であり，Virtual Address Spaceに対するPage TableのMappingを行う．
使用時にArchitecture-Specificな知識を必要とせず，階層構造はDepthによって管理される．

x86_64におけるPage Tableを例示する．
x86_64 Architectureは通常4レベルのPage Tableを持つ．
まだPage TableがMapされていない状態を仮定してVirtual AddressをMapすることを考える．
+ PML4はAddress Space Capabilityそのものである．
+ PDPTはDepth : 3のPage Table Capabilityである．
+ PDはDepth : 2のPage Table Capabilityである．
+ PTはDepth : 1のPage Table Capabilityである．
以上3つのPage TableをAddress SpaceにMap後，Address Spaceの`get_unset_depth`を実行すると0が返される．
Depth : 0はFrame Capabilityに対応するため，これをMapすることでVirtual Address Spaceに対するMappingが完了する．

==== Architecture-IndependentなVirtual Memory Management

Architecture-Specificな知識を必要としないPortableなVirtual Memory Management Serverを実現する場合，典型的にはまず空のAddress Space Capabilityに対して`get_unset_depth`を実行することが推奨される．ここで得た値はそのまま必要なPage Tableの数とDepthに対応するためである．

もちろん，簡易化のために初めからDepthを指定してPage Table Capabilityを作成することも可能である．このような実装はSystemのPortabilityを損なうが，Project開始時のPrototypeとしては有用である．

==== Capability Call

現時点でPage Table CapabilityにCapability Callは存在しないが，将来的にそれ自体のDepthを確認するための`get_depth`が追加される予定である．

=== Frame Capability

Frame CapabilityはPhysical Memory Frame (i.e., Page)を抽象化したCapabilityである．
Frame CapabilityもPage Table Capabilityと同様にAddress Space CapabilityにMap可能である．したがって，同じFrameを複数のAddress SpaceにMapすることでShared Memoryを実現することができる．

==== Capability Call

#technical_term(name: `get_address`)[対象Frameが指すPhysical Memory Regionの先頭Physical Addressを得る．]

#figure(
    api_table(
        "capability_descriptor", "memory_descriptor", "対象FrameへのDescriptor"
    ),
    caption: [`get_address`の引数]
)

#figure(
    api_table(
        "physical_address", "address", "Frameが指しているPhysical Address"
    ),
    caption: [`get_address`の返り値]
)

#pagebreak()

=== Process Control Block Capability

Process Control Blockは，従来のSystemにおけるProcessを抽象化したCapabilityである．
Hardware ContextとTime Slice，そしていくつかのCapabilityを持ち，SchedulerによってScheduleされる対象である．
ただし，従来の概念とは異なり提供する機構が最小に保たれる．
したがって，ProcessやThreadといった概念の実現にはUser-Levelでの適切なConfigurationが必要である．

==== Capability

Process Control BlockにはいくつかのCapabilityをConfigurationすることができる：

#v(1em)

#technical_term(name: "Root Node")[
    Process Control Blockが使用するRootとなるCapability Node．
    このProcess Control BlockがCapability Callを実行したとき，指定されたCapability DescriptorはRoot Nodeを起点に探索される．
]

#technical_term(name: "Root Address Space")[
    Process Control BlockのVirtual Address Spaceが規定されるAddress Space Capability．
    このCapabilityを起点としてAddress SpaceのSwitchが行われ，またVirtual Memory Managementが実現される．
]

#technical_term(name: "Buffer Frame")[
    IPC Bufferとして使用するFrame Capability．
    Frame Capabilityを用いることでBufferの存在を保証できる．したがって，安全にKernel-User間のCommunicationを実現できる．
]

#technical_term(name: "Resolver Port")[
    Process Control Blockの実行中にExceptionが発生した場合に，そのStatusを送信するためのIPC Port Capability．
    Exception Status Messageを受信した対象はその内容に応じて適切な処理を行い，Exceptionの発生元を再開できる．
    Exceptionの発生時にResolver Portが設定されていない場合はDouble Faultとして動作を停止する．

    // TODO: いい感じの図を作る
]

Process Control Blockに必要なCapabilitiyをConfiguration後#footnote[Root Address Spaceは必須だが，その他のCapabilityはあくまでもOptionalである]，Resume操作を実行することでSchedulerのQueueに登録される．
Benno Schedulerは前述の通り実行可能なContextのみをQueueとして持つため，PriorityやTime Sliceが考慮されたあとに実行が行われる．

==== Capability Call

#technical_term(name: `configure`)[Process Control BlockをConfigurationする．]

#api_table(
    "capability_descriptor", "process_control_block", "対象Process Control BlockへのDescriptor",
    "configuration_info", "info", [cf., @process_control_block::configuration_info],
    "capability_descriptor", "root_page_table", "Root Page TableへのDescriptor",
    "capability_descriptor", "root_node", "Root NodeへのDescriptor",
    "capability_descriptor", "frame_ipc_buffer", "IPC BufferとしたいFrameへのDescriptor",
    "capability_descriptor", "notification_port", "Notification PortへのDescriptor",
    "capability_descriptor", "ipc_port_resolver", "ResolverとしたいIPC PortのDescriptor",
    "virtual_address", "instruction_pointer", "Instruction Pointer",
    "virtual_address", "stack_pointer", "Stack Pointer",
    "virtual_address", "thread_local_base", "Thread Local Base",
    "word", "priority", "優先度",
    "word", "affinity", "SMP環境におけるAffinity (CPU CoreのIndex)",
)

Performanceのため，Process Control Blockにおける各ParameterはConfiguration Info (@process_control_block::configuration_info)によって一括してConfigurationできる．

#figure(
    bytefield(
        bpr: 16,
        rows: (14em),
        bitheader(
            "bounds",
            0,
            8,
            15,
            text-size: 8pt,
        ),

        flag[ROOT_PAGE_TABLE],
        flag[ROOT_NODE],
        flag[FRAME_IPC_BUFFER],
        flag[NOTIFICATION_PORT],
        flag[IPC_PORT_RESOLVER],
        flag[INSTRUCTION_POINTER],
        flag[STACK_POINTER],
        flag[THREAD_LOCAL_BASE],
        flag[PRIORITY],
        flag[AFFINITY],
        bits(6)[RESERVED],

        text-size: 4pt,
    ),
    caption: "Configuration Info"
) <process_control_block::configuration_info>

Configuration Infoの各BitがそれぞれのFieldに対応する．
このBitが立っている場合，そのFieldがConfigurationされる．逆に言えば，立っていない場合そのFieldに対応する引数は無視される．

#v(1em)

#technical_term(name: `read_register`)[
    Process Control BlockのRegister (Hardware Context) を読み出す．
    読み出したRegisterはMessage RegisterのIndex:3#footnote[Index:0とIndex:1はCapability Resultによって予約されている．また，そのまま`write_register`を実行してコピーを可能とするためにIndex:2も予約されている．]から
    n#footnote[Architectureに依存．詳細はABIを参照．]へ格納される．
]

#figure(
    api_table(
        "capability_descriptor", "process_control_block", "対象Process Control BlockへのDescriptor",
        "word", "register_count", "読み出すRegisterの数",
    ),
    caption: [`read_register`の引数]
)

#figure(
    api_table(
        "word[n]", "registers", "読み出したRegisterの値",
    ),
    caption: [`read_register`の返り値]
)

#technical_term(name: `write_register`)[
    Process Control BlockにRegister (Hardware Context) を書き込む．
    Message RegisterのIndex:3からIndex:nを読み出し，対象Process Control BlockのRegisterに書き込む．
]

#api_table(
    "capability_descriptor", "process_control_block", "対象Process Control BlockへのDescriptor",
    "word", "register_count", "書き込むRegisterの数",
    "word[n]", "registers", "書き込むRegisterの値",
)

#technical_term(name: `resume`)[Process Control Blockを実行可能状態にし，SchedulerのQueueに追加する．]

#api_table(
    "capability_descriptor", "pcb_descriptor", "対象Process Control BlockへのDescriptor",
)

#technical_term(name: `suspend`)[Process Control Blockを休止状態にする#footnote[休止状態のProcess Control BlockはQueueに追加されない．したがって，明示的に再開するまで実行されない．]．]

#api_table(
    "capability_descriptor", "pcb_descriptor", "対象Process Control BlockへのDescriptor",
)

#pagebreak()

=== IPC Port Capability

A9N MicrokernelはIPC PortによるRendezvous Indirect IPCを採用している．
ある実行可能なContextがIPC PortへMessageをSendすると，同じIPC Portを持つ他のContextがそのMessageをReceiveできる．
SenderとReceiverは1:nもしくはn:1の関係を持つ．

例えばある$"IPCPort"_"A"$が存在したとして，$"Context"_"A"$が$"IPCPort"_"A"$にSend操作を実行したとする．
この状態ではReceiverとなるContextが存在しないため，$"Context"_"A"$はBlockされ，$"IPCPort"_"A"$のWait Queueに追加される．
さらに$"Context"_"B"$が$"IPCPort"_"A"$へSend操作を実行すると，やはりReceiverが存在しないためBlockされ，$"IPCPort"_"A"$のWait Queueに追加される．
ここで，Receiverとなる$"Context"_"C"$が$"IPCPort"_"A"$へReceive操作を実行すると，$"IPCPort"_"A"$が持つWait Queueの先頭から$"Context"_"A"$が取り出され，$"Context"_"A"$の持っていたMessageが$"Context"_"C"$にCopyされる．
このを例を図示すると (@ipc_port::send_receive_example) のようになる．

#figure([
    #import "@preview/fletcher:0.5.5" as fletcher: diagram, node, edge

    // utility
    #let sender(name, pos) = (node((pos), name))
    #let receiver(name, pos) = (node((pos), name))

    #diagram(
        // initialize
        node-stroke: 0.1em,
        node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: 4em,
        node-inset: 1em,


        // draw nodes
        sender([$"Context"_"A"$], (0, 0)),
        sender([$"Context"_"B"$], (0, 1)),
        node((2, 0.5), "IPC Port"),
        receiver([$"Context"_"C"$], (4, 0.5)),
        // dirty hack
        edge((0, 1), (0.75, 1), (0.75, 0.5), (2, 0.5), "-|>", label-side: center, label-pos: 85%),
        edge((0, 0), (0.75, 0), (0.75, 0.5), (2, 0.5), [`send`], "-|>", label-side: center, label-pos: 85%),
        // edge((0, 1), (2, 0.5), [`send`], "-|>"),
        edge((0, 0), (2, 0),(2, 0.5), box(inset: 0em)[Enqueue], "-|>", label-pos: 20%),
        edge((0, 1), (2, 1),(2, 0.5), box(inset: 1em)[Enqueue], "-|>", label-pos: 20%, label-anchor: "north"),
        edge((4, 0.5), (2, 0.5), [`receive`], "-|>"),
        edge((4, 0.5), (3.45, 0.5), (3.45, 0), (2, 0), (2, 0.5), [Dequeue], "-|>", label-pos: 58%, label-anchor: "south"),
        edge((0, 0), (0, -0.5), (4, -0.5), (4, 0.5), [Send Message], "..|>"),
    )
    ],
    caption: "IPC Send/Receive Example"
) <ipc_port::send_receive_example>

この例はSender:Receiverがn:1の場合を示すが，Sender:Receiverが1:nの場合も同様である．

ここで重要なのが，IPC PortはMessageをBufferingしないという事実だ．IPC PortはSender/ReceiverのQueueを保持するが，これはMessageのQueueではない．
MessageはSenderのVirtual Message RegisterからReceiverのVirtual Message Registerへ*直接*Copyされるため高速である．

==== Non-Blocking IPC

SendやReceive操作はNon-Blockingで実行することも可能である．
基本的には前節と同様だが，QueueにSender/Receiverが存在しない場合Blockせず即座にReturnする．

==== Call/Reply Mechanism

先述したSendやReceive操作は一方向の通信であり，基本的に使用は推奨されない．
そのため，IPC PortはCallとReply，Reply ReceiveというClient-Sever Modelに特化した操作の仕様が推奨される．

#v(1em)
#technical_term(name: `call`)[
    IPC Portから取得したContextに対してSendしReplyを待つ．
    概念的にはSendとReceiveを組み合わせたものに近いが，この操作を実行したContextから見たときAtomicに送受信が実行される点が異なる．
    言い換えると，MessageをSendした対象であるReceiverからMessageを受信することを保証できる．

    この操作を実現するため，Call時にそのCallerはReceiverへReply Objectを設定する．
    このReply ObjectはReply StateとReply Target部によって構成される．

    Reply StateはReply Objectの状態を示し，SourceとDestinationの2つが存在する．
    Callを実行し，Replyを待っている場合にWAITが設定される．
    

    ```cpp
    enum class source_reply_state_object : a9n::word
    {
        NONE,
        WAIT,
    } source_reply_state { source_reply_state_object::NONE };

    enum class destination_reply_state_object : a9n::word
    {
        NONE,
        READY_TO_REPLY,
    } destination_reply_state { destination_reply_state_object::NONE };

    // NOTE: *Why do we need source_reply_target?*
    // Suppose that process A is in the middle of a call to process B and A is destroyed (e.g.,
    // via Revoke/Remove). Although process B has A as the reply target, it will hold a pointer
    // to an invalid process (A in this case) that has already been destroyed.
    // Therefore, it is necessary to allow the caller to refer to the callee.
    process *source_reply_target;
    process *destination_reply_target;
    ```

    // TODO: いい感じの図を作る
]

#technical_term(name: `reply`)[
]

==== Direct Context Switch

Aは @ElphinstoneEtAl:2013 を
==== Capability Call

A9N MicrokernelにおけるIPCは第一級のKernel Callではなく，あくまでもIPC Portに対するCapability Callとして提供される．

#pagebreak()

=== Notification Port Capability

=== Interrupt Region Capability

=== Interrupt Port Capability

=== IO Port Capability

=== Virtual CPU Capability

=== Virtual Address Space Capability

=== Virtual Page Table Capability

=== ABI

=== Boot Protocol

=== Init Protocol

== Nun Operating System Frameworkの開発

=== Build System 

=== HAL

=== Entry Point

=== API

/* ===== KOITO ===== */

== KOITOの開発

=== Standard C Library

// CMake Integration

=== Memory Management Server

=== POSIX Server

/* ===== liba9n ===== */

== `liba9n`の開発

=== `liba9n::std`

=== `liba9n::option<T>`

=== `liba9n::result<T, E>`

=== Monadic Operation

=== Conditionally Trivial Special Member Functions

=== `liba9n::not_null<T>`

/* ===== A9NLoader ===== */

== A9NLoaderの開発

=== Init ServerのLoad

=== ELF Symbolの解決

=== CMake Integration
