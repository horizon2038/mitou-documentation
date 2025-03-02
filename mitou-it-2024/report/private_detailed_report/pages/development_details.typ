#import "/components/api_table.typ" : *
#import "@preview/bytefield:0.0.7": *
#import "@preview/cetz:0.3.2"
#import "@preview/fletcher:0.5.5" as fletcher: diagram, node, edge

#import "/components/term.typ" : *

= 開発内容

/* ===== A9N ===== */

== A9N Microkernelの開発

=== History of A9N Microkernel

=== Basic Types <a9n::basic_types>

A9N MicrokernelはC++20を用いて開発されているが，Kernel内部で広範に使用するための基本型を定義している．
Kernel内部では幅が固定された型を基本的に使用せずに`word`型を使用する．
`word`はArchitecture-SpecificなWord幅を持つ符号なし整数型であり，`uintmax_t`や`usize`のAliasとして定義される．
これにより，速度と移植容易性を実現する．

A9NにおけるKernelの呼び出し機構はC ABIに依存しないVirtual Message Register-Basedなものである．
したがって，Kernelは多値の返却や正常値とエラー値の区別が可能な形式でUserに制御を返すことができる．
そのため，言語のLibraryレベルでMapperを作成することにより，NativeなResult型やその他の型を返すことができる．
このようなAPIのRustによるReference ImplementationはNun OS Frameworkに内包されている．

=== API Primitive <a9n::api_primitive>

A9N MicrokernelはUserに対してKernel Callを提供する．
Kernel Callは細分化することができ，以下2 + 1個のAPIを提供する．これらは従来型SystemにおけるSystem Callに相当するものである:

+ Capability Call
+ Yield Call
+ Debug Call

従来型のSystem，例えばLinux KernelのSystem Call数は2024年時点で300を超える @LinuxSyscalls:2024 が，A9Nはその1/100程度でSystemを構築することが可能である．

=== Capability Overview <a9n::capability_overview>

// Capabilityの基礎概念を説明する
A9N Microkernelの実装にはObject-Capability Model @DennisEtAl:1966 によるCapability-Based Securityを採用し，従来のシステムが抱えていた課題を解消した．
Capabilityは特権的リソース : Objectに対するアクセス権限を示すUniqueなTokenである．
従来のACLを用いたアクセス ── リソース自身がPermissionを確認する方式とは異なり，該当Capabilityの所有者のみが操作を実行可能である．
このように，PoLPを満たしつつも柔軟なアクセス制御を実現する．

言い換えるとCapabilityはTokenであり，間接的にObjectへアクセスするためのHandleである．
要するに，あらゆる特権的操作はObjectが持つ固有機能の呼び出しとしてModel化される．したがって，Object-Oriented ProgrammingにおけるObjectのMethod Callと同等に捉えることができる．
また，CapabilityとObjectを同一視することもできる．よって，この文書ではCapabilityとObjectを同義として扱う．

Capabilityは複数のContext間でCopyやMoveが可能である．この仕組みにより，UserはCapabilityをServer間で委譲して特権的な操作の実行範囲を最小化できる．

=== Capabilityの操作体系 <a9n::capability_operation>

A9N Microkernelにおいて，操作対象のCapabilityを指定するためにCapability Descriptorと呼ばれる符号なし整数型を用いる．
Capability Descriptorは後述するCapability Nodeを再帰的に探索するためのAddressである．
Capability Callの実行時，First ArgumentとしてCapability Descriptorを指定する (@capability_call_pseudo_code) ことでRoot Capability Nodeから対象が暗黙的に探索される．

#figure(
    ```rust
    fn capability_call(target: capability_descriptor, args ...) -> capability_result
    ```,
    caption: "Capability CallのPseudo Code",
) <capability_call_pseudo_code>

=== Capability Slot <a9n::capability_slot>

Capabilityは内部的にCapability Slotと呼ばれるデータ構造に格納される．
Capability SlotはCapability ComponentへのPointerとSlot Local Data，Capability Rights，Dependency Nodeから構成される．

==== Capability Component <a9n::capability_component>

すべてのCapabilityをC++上で統一的に扱うため，Capability ComponentというInterface Classを定義する (@a9n::capability_component::definition)．
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
) <a9n::capability_component::definition>

すべてのCapabilityはCapability Componentの実装である．

==== Slot Local Data <a9n::slot_local_data>

SlotにCapability ComponentへのPointerを格納するだけでは問題が生じる．
例えばProcess Control BlockのようなCapabilityを考えると，これはComponentとしてのInstanceごとに状態を持つため問題は発生しない．
しかしながらMemoryに関連するCapability(e.g., Generic, Page Table, Frame)を考えたとき，これらのために1つずつUniqueなInstanceを生成していては効率が悪い．
よって，そのようなUsecaseに対応するためSlot Local Dataを導入した．
対象のCapabilityはSlot Local Dataにそれらの情報を保持し，Capability Componentとして指すInstanceはCapabilityごとに単一のものを共有するようなアプローチを取ることができる．
これにより，Memoryの新規Allocationを必要とせずにCapabilityを生成可能とした．
このSlot Local Dataという仕組みはMemoryに関連するCapabilityに限らず有用であり，どのように利用するかはCapability Componentの実装によって決定される．

==== Capability Rights <a9n::capability_rights>

前述した通り，一部の例外を除いてCapabilityはCopyやMoveが可能である．
CapabilityがCopyされた場合，DestinationとSourceは同一のCapabilityとして扱われる．

しかし，これらのCapabilityに対して別々のアクセス制御を実行したいUsecaseが存在する．
典型例として，IPC Port Capabilityを親が子に共有するが，子からはこのCapabilityを削除できないようにしたい#footnote()[Dependency Nodeを除いて親や子といった概念はKernelに存在しない．これはKernelを使用するOS Layerでみたときの例である．]場合がある．
このようなシナリオに対応するため，Capability Slot固有のCapability Rightsを導入した．
Capability RightsはCapabilityのCopyやRead，Writeに対する挙動を制御するためのBit Flagである (@a9n::capability_rights::definition)．

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
) <a9n::capability_rights::definition>

Capability Rightsには，先天的に設定されるものと後天的に設定するものの両方が存在する．
原則として，Capabilityは生成時点にすべてのRights Bitが設定される．
ただし，Copyを許可すると同一性が失われてしまうようなCapabilityはCopyが最初から禁止される．

==== Dependency Node <a9n::dependency_node>

Capabilityはその依存関係をDependency Node (@a9n::dependency_node_definition) によって管理する．
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
) <a9n::dependency_node_definition>

- 親の区別は可能だが，通常使用されないため省略される．
- `next_slot`もしくは`preview_slot`の`depth`が自分自身の`depth`と等しい場合，そのSlotは兄弟である．
- `next_slot`の`depth`が自分自身の`depth`よりも大きい場合そのSlotは子である．子は必ず`next_slot`側に設定されるため，`preview_slot`の`depth`は比較しない．

Dependency Nodeは所有関係を表すものではなく，あくまでも派生と同一性を表すために利用される．

#pagebreak()

=== Virtual Message Register <a9n::virtual_message_register>

A9N MicrokernelではCapability CallのためにVirtual Message Register#footnote[L4 Microkernel FamilyにおけるUTCBと同等]機構を使用する．
Virtual Message Registerはその名の通り，Communicationに使用するためのMessageを格納するRegisterである．

- ArchitectureごとにVirtual Message RegisterはHardware RegisterへMapされる#footnote()[ABI項を参照]．
- Hardware RegisterにMapできないMessage#footnote()[ABI項を参照]はProcess Control BlockごとのIPC Bufferに格納される．IPC BufferはKernelとUser間のShared Memoryであり，必ず存在が保証される．

このアプローチは高速かつSecureなCapability Callを実現する．

- Hardware RegisterへのAccessは一般に高速であるため，Message CopyのOverheadを最小限に抑えることができる．
- IPC BufferはCapabilityによって存在が保証されるため，Kernel SpaceにおけるUser Space起因のPage Faultは発生しない．

=== Scheduler <a9n::scheduler>

A9N MicrokernelはBenno Scheduler @ElphinstoneEtAl:2013 をProcess Schedulingに使用する．
Priority-Based Round-Robin Schedulerであり，255段階のPriority Levelを持つ．
基本的には従来のSchedulerと同じだが，Benno Schedulerが異なる点は必ず実行可能なProcessのみをQueueに保持するところにある．
このアプローチはQueue操作を簡易化し，なおかつHot-Cache内の実行による高速化を実現することができる．
その結果，SystemはLow Latencyとなる．

=== Kernel-Level Stack <a9n::kernel_stack>

A9N MicrokernelはEvent Kernel Architectureであり，Kernel StackをCPUコアごとに割り当てるSingle Kernel Stack @Warton:2005 アプローチを採用している．
従来のProcess Kernel Architectureでは実行可能なContextごとに4-8KiBのKernel Stackを割り当てていたが，この方式では大量のKernel Memoryを消費してしまう欠点がある．
CPUコアごとのKernel StackはMemory Footprintを削減し，実行可能Context数のScalabilityを向上させる．

// TODO: いい感じの図を作る

#pagebreak()

=== Capability Callの略式表記 <a9n::capability_call::abbreviation>

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

=== Capability Node <a9n::capability_node>

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
+ Capability DescirptorからDescriptor Used Bits分をSkipした箇所からNodeのRadix Bits分を取り出し (@a9n::capability_node::calculate_capability_index) ，Node Indexとする．
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
) <a9n::capability_node::calculate_capability_index>

Node以外のCapability Component実装は，`retrieve_slot`や`traverse_slot`の呼び出し時に`capability_lookup_error::TERMINAL`を返す．この機構により，どのCapability Componentを呼び出すかに関わらずCapability Nodeの探索を行うことができる．

==== Addressing <a9n::capability_node::addressing>

Capability Callの実行時，対象となるCapabilityは指定されたCapability Descriptorを用いて暗黙のうちにRoot Capability Nodeから探索される．
Userが指定したCapability Descriptorの先頭8bitはDepth Bitsであり (@a9n::capability_descriptor)，Capability Nodeの探索上限を示す．

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
) <a9n::capability_descriptor>

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

これを図示すると (@a9n::capability_node::example) になる．

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
) <a9n::capability_node::example>

ここで, $"Capability"_"Target"$を対象としてCapability Callを実行したい場合を考えると，Capability Descriptorは (@a9n::capability_node::example::target_descriptor) のようになる#footnote()[簡略化のために32bit ArchitectureにおけるDescriptorを例示しているが，異なるWord幅のArchitectureにおいても同様の構造をとる．]:

//   0001 1000 = 0x24 (depth)
//   0000 0011 = 0x02 (node_0)
// 000000 0011 = 0x03 (node_1)
//     00 0101 = 0x04 (node_2)
#text()[$
    "capability_descriptor"        &:= &"0x"&"180300C5" &("hex") \ 
                        &:= &"0b"&"00011000000000110000000011000101" &("bin")
$] <a9n::capability_node::example::target_descriptor>
// 00011000'00000011'00000000'11000101

これをNodeのRadix Bitsによってパースすると，(@a9n::capability_node::example::parsed_capability_target_descriptor) となる:

$
    0b
    overbracket(underbracket(00011000, "Depth"), "8bit")
    overbracket(underbracket(00000011, "Index"_("Node"_0)), "8bit")
    overbracket(underbracket(0000000011, "Index"_("Node"_1)), "10bit")
    overbracket(underbracket(000101, "Index"_("Node"_2)), "6bit")
$ <a9n::capability_node::example::parsed_capability_target_descriptor>

まず，先頭8bitからDepth Bitsが取り出される．この場合は$"0b00011000" = "0x24"$となる．
Depth Bitsの妥当性を示すため，実際に計算を行う．

$"Capability"_"Target"$に対応するDepth Bitsは (@a9n::capability_node::example::capability_target_calculated_depth)のように計算される：

$
    "Depth"("Capability"_"Target") &= "Radix"("Node"_0) + "Radix"("Node"_1) + "Radix"("Node"_2) \ 
    &= 8 + 10 + 6 = 24
$ <a9n::capability_node::example::capability_target_calculated_depth>

ただし，$"Capability"_"Target"$のように終端まで探索を行う場合，Depth Bitsはその最大値を用いることができる (@a9n::capability_node::example::capability_max_depth)：
$
    "Depth"_"Max" = "WordWidth" - 8
$ <a9n::capability_node::example::capability_max_depth>

続いて，$"Node"_0$を探索するためのIndexを取得する．$"Node"_0$のRadix Bitsより8bitを取り出し，取得した$"0x02"$を$"Index"_("Node"_0)$とする．
これを用いて$"Node"_0$から$"Node"_1$を得る．

次に，$"Node_1"$を探索するためのIndexを取得する．$"Node_1"$のRadix Bitsより8bitを取り出し，取得した$"0x03"$を$"Index"_("Node"_1)$とする．
これも同様に$"Node_1"$のIndexとし，$"Node_2"$を得る．

最後に，$"Node_2"$を探索するためのIndexを取得する．$"Node_2"$のRadix Bitsより8bitを取り出し，取得した$"0x04"$を$"Index"_("Node_2")$とする．
これにより，最終的な$"Capability"_"Target"$が取得される．

次の例として，$"Node"_1$を対象にCapability Callを実行したい場合を考えると，Capability Descriptorは (@a9n::capability_node::example::capability_node_1_descriptor) のようになる:

#text()[$
    "capability_descriptor"        &:= &"0x"&"803xxxx" &("hex") \ 
                        &:= &"0b"&"0000100000000011 xxxxxxxxxxxxxxxx" &("bin")
$] <a9n::capability_node::example::capability_node_1_descriptor>

これをNodeのRadix Bitsによってパースすると，(@a9n::capability_node::example::parsed_node_1_descriptor) となる:

$
    0b
    overbracket(underbracket(00001000, "Depth"), "8bit")
    overbracket(underbracket(00000011, "Index"_("Node"_0)), "8bit")
    overbracket(underbracket("XXXXXXXXXXXXXXXX", "Unused"), "Remain Bits")
$ <a9n::capability_node::example::parsed_node_1_descriptor>

これも同様にDepth Bitsの妥当性を検証する．
この場合，Depth Bitsは (@a9n::capability_node::example::capability_node_1_depth)のように計算される：

$
    "Depth"("Capability"_"Target") &= "Radix"("Node"_0) \ 
    &= 8
$ <a9n::capability_node::example::capability_node_1_depth>

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
) <a9n::capability_node::copy>

#technical_term(name: `move`)[CapabilityのMoveを実行する．RightsはそのままMoveされる．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "destination_index", "DestinationとなるCapabilityを格納しているNode内Index",
    "capability_descriptor", "source_descriptor", "SourceとなるNodeのDescriptor",
    "word", "source_index", "SourceとなるNodeのCapabilityを格納しているIndex",
) <a9n::capability_node::move>

#technical_term(name: `mint`)[CapabilityのMintを実行する．新しいRightsは元となるRightsのSubsetである必要がある．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "destination_index", "DestinationとなるCapabilityを格納しているNode内Index",
    "capability_descriptor", "source_descriptor", "SourceとなるNodeのDescriptor",
    "word", "source_index", "SourceとなるNodeのCapabilityを格納しているIndex",
    "capability_rights", "new_rights", "新しいRights (cf., @a9n::capability_rights)",
) <a9n::capability_node::mint>

#technical_term(name: `demote`)[Capability Rightsを不可逆的に降格する．新しいRightsは元となるRightsのSubsetである必要がある．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "target_index", "対象のCapabilityを格納しているNode内Index",
    "capability_rights", "new_rights", "新しいRights (cf., @a9n::capability_rights)",
) <a9n::capability_node::demote>

#technical_term(name: `remove`)[CapabilityをSlotから削除する．Dependency Nodeに兄弟が存在しない場合，Revokeを実行してから削除する．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "target_index", "削除対象のCapabilityを格納しているNode内Index"
) <a9n::capability_node::remove>

#technical_term(name: `revoke`)[Capabilityを初期化/無効化する．]

#api_table(
    "capability_descriptor", "node_descriptor", "対象Capability NodeへのDescriptor",
    "word", "target_index", "削除対象のCapabilityを格納しているNode内Index"
) <a9n::capability_node::revoke>


#pagebreak()

=== Generic Capability <a9n::generic>

Generic Capabilityは物理的なMemoryを抽象化したCapabilityである．
GenericはBase Address，Size Radix Bits，Watermark，そしてDevice Bitsから構成される．

- Base AddressはGenericが指すMemory Regionの開始Physical Addressである．
- Size Radix BitsはGenericが指すMemory RegionのSizeを示すRadixであり，$2^"SizeRadixBits"$が実際のSizeである．この事実から分かるように，GenericのSizeは必ず2の累乗byteである．
- WatermarkはGenericの使用状況を示すPhysical Addressである．
- Device BitsはMemory RegionがDeviceのために使用されるような場合(e.g., MMIO)に設定される．

Generic CapabilityはすべてのCapabilityを生成するためのFactoryとして機能する．
Convert操作 によってGeneric Capabilityの領域を消費し，新たなCapabilityを生成することができる．
生成したCapabilityはDependency Nodeへ子として設定され，破棄の再帰的な実行に利用される．

==== $log_2$ Based Allocation

GenericのConvert操作時，次のステップでCapabilityを生成する：

+ Convert操作によって指定されたCapability TypeとSpecific BitsからSize Radixを得る．
+ Size Radix分をAllocate可能か確認する．
+ WatermarkをSize RadixにAlign(Ceil)し，WatermarkにSize Radix分を加算する．

#v(1em)

まず，引数として与えられたCapability TypeとSpecific BitsからSize Radixを取得する．
Capability ObjectのSizeを最も近い2の累乗に切り上げ, 2を底とする対数をとる (@a9n::generic::calculate_radix_ceil)．

#figure(
    $ "SizeRadix" = ceil.l log_2("Sizeof"("Object")) ceil.r $,
    caption: "Size Radixの計算"
) <a9n::generic::calculate_radix_ceil>

Specific Bitsが必要となる理由は，Specific Bitsによって全体としてのSizeが決定されるCapability NodeのようなCapabilityが存在するためである．

次に，Size Radix分のMemory領域がAllocate可能か確認する．Allocateした場合のWatermarkを計算し (@a9n::generic::calculate_new_watermark) ，

#figure(
    $
        "NewWatermark" = "SizeRadix" dot stretch(ceil.l, size: #150%) frac("Watermark", "SizeRadix") stretch(ceil.r, size: #150%)
    $,
    caption: "Size RadixにAlignされたWatermarkを計算"
) <a9n::generic::calculate_new_watermark>

それが範囲内か確認する (@a9n::generic::check_new_boundary)．

#figure(
    $
        "NewWatermark" < "Watermark" + 2^"RadixBits" and \ 
        "NewWatermark" + 2^"SizeRadix" * "Count" <= "BaseAddress" + 2^"RadixBits"
    $,
    caption: "Allocationのための境界チェック"
) <a9n::generic::check_new_boundary>

そして，最後にAllocateを実行する．

このように，すべてのCapabilityはAllocate時にAlignされる．そのため，Genericを適切に分割してからCapabilityをConvertすることで自然と*SLAB Allocator*のような振る舞いを実現する#footnote[あるCapabilityのConvertによってAlignが発生すると，次の同一CapabilityをConvertする際に隙間なくAllocateできるため．]．

==== Deallocation

Genericの再利用には，ConvertされたすべてのCapabilityをRemoveする必要がある．
これはGenericに対してRevokeを実行することで再帰的に行われる．
すなわち，ある$"Capability"_"A"$をConvertしたあとに$"Capability"_"B"$をConvertし，$"Capability"_"A"$をRemoveしても$"Capability"_"A"$が使用していた領域を再利用できない．
これはGenericの構造を考えれば明らかである．Genericは単純化と高速化のために単一のWatermarkのみで使用量管理を実現している．したがって，高粒度な再利用をKernelは提供しない．
その実現には，Genericから再利用単位ごとに子となるようなGenericを生成する必要がある#footnote[この実装は完全にUser-Levelで実現される．]．

==== Capability Call

#technical_term(name: `convert`)[Generic Capabilityの領域を指定されたCapability Typeに変換する．]

#api_table(
    "capability_descriptor", "generic_descriptor", "対象GenericへのDescriptor",
    "capability_type", "type", "生成するCapabilityのType",
    "word", "specific_bits", [Capability生成時に使用する固有Bits \ cf., @a9n::generic::specific_bits],
    "word", "count", "生成するCapabilityの個数",
    "capability_descriptor", "node_descriptor", "格納先NodeへのDescriptor",
    "word", "node_index", "格納先NodeのIndex",
)

Specific Bits (@a9n::generic::specific_bits) はCapability Type依存の初期化に使用する値である．例えば，Capability NodeをConvertする時に指定するSpecific BitsはNodeのRadixとなる．

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
) <a9n::generic::specific_bits>

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

もちろん，簡易化のために初めからDepthを指定してPage Table Capabilityを生成することも可能である．このような実装はSystemのPortabilityを損なうが，Project開始時のPrototypeとしては有用である．

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
    Process Control Blockの実行中にExceptionが発生した場合に，そのStatusをFault Callとして送信するためのIPC Port Capability．
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
    "configuration_info", "info", [cf., @a9n::process_control_block::configuration_info],
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

Performanceのため，Process Control Blockにおける各ParameterはConfiguration Info (@a9n::process_control_block::configuration_info)によって一括してConfigurationできる．

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
) <a9n::process_control_block::configuration_info>

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
この例を図示すると (@a9n::ipc_port::send_receive_example) のようになる．

#figure([
    // utility
    #let sender(name, pos) = (node((pos), name, fill: none))
    #let receiver(name, pos) = (node((pos), name, fill: none))

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
        node(enclose: ((0, 0), (0, 1)), inset: 10pt, snap: false, fill: none, stroke: 0.05em),

        node((2, 0.5), "IPC Port"),

        receiver([$"Context"_"C"$], (4, 0.5)),

        // dirty hack
        edge((0, 1), (0.75, 1), (0.75, 0.5), (2, 0.5), "-|>", label-side: center, label-pos: 85%),
        edge((0, 0), (0.75, 0), (0.75, 0.5), (2, 0.5), [`send`], "-|>", label-side: center, label-pos: 86%),
        edge((0, 0), (2, 0),(2, 0.5), box(inset: 0em)[Enqueue], "-|>", label-side: center, label-pos: 30%),
        edge((0, 1), (2, 1),(2, 0.5), box(inset: 0em)[Enqueue], "-|>", label-side: center, label-pos: 31%, label-anchor: "north"),
        edge((4, 0.5), (2, 0.5), [`receive`], "-|>", label-side: center),
        edge((4, 0.5), (3.45, 0.5), (3.45, 0), (2, 0), (2, 0.5), [Dequeue], "-|>", label-side: center, label-pos: 58%, label-anchor: "south"),
        edge((0, 0), (0, -0.5), (4, -0.5), (4, 0.5), [Send Message], "..|>", label-side: center),
    )
    ],
    caption: "IPC Send/Receive Example"
) <a9n::ipc_port::send_receive_example>

この例はSender:Receiverがn:1の場合を示すが，Sender:Receiverが1:nの場合も同様である．

ここで重要なのが，IPC PortはMessageをBufferingしないという事実だ．IPC PortはSender/ReceiverのQueueを保持するが，これはMessageのQueueではない．
MessageはSenderのVirtual Message RegisterからReceiverのVirtual Message Registerへ*直接*Copyされるため高速である．

==== Non-Blocking IPC

SendやReceive操作はNon-Blockingで実行することも可能である．
基本的には前節と同様だが，QueueにSender/Receiverが存在しない場合Blockせず即座にReturnする．

==== Call/Reply Mechanism

先述したSendやReceive操作は一方向の通信であり，双方向通信にはコストが発生するため基本的に推奨されない．
そのため，IPC PortはCallとReply，Reply ReceiveというClient-Sever Model (@client_server_model) に特化した操作の仕様が推奨される．

#figure([ 
    #diagram(
        // initialize
        node-stroke: 0.1em,
        // node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: 2em,
        node-inset: 1em,

        // draw nodes
        node((0, 0), "Client"),
        node((2, 0), "Server"),
        node((1, 1), block(inset: (x: 4em))[Microkernel]),

        edge((0, 0), (0, -1), (2, -1), (2, 0),  [Call], "..|>", label-side: center),
        edge((2, 0), (0, 0), [Reply], "..|>", label-side: center),

        edge((0, 0), (0, 1), (1, 1), [Message], "<|-|>"),
        edge((1, 1), (2, 1), (2, 0), block(inset: (x: 1em))[Message], "<|-|>", label-anchor: "west"),
    )
    ],
    caption: "Client-Server Model"
) <client_server_model>

これらは双方向通信を1つのPathで実行するための操作であり，これによってContext Switchのコストを抑え，なおかつ高度な最適化を実現する．

#v(1em)
#technical_term(name: `call`)[
    IPC Portから取得したContextに対してSendしReplyを待つ．
    概念的にはSendとReceiveを組み合わせたものに近いが，この操作を実行したContextから見たときAtomicに送受信が実行される点が異なる．
    言い換えると，MessageをSendした対象であるReceiverからMessageを受信することを保証できる．

    この操作を実現するため，Call時にそのCallerはReceiverへReply Objectを設定する．
    このReply ObjectはReply StateとReply Target部によって構成される．

    Reply StateはReply Objectの状態を示し，SourceとDestinationの2つ存在する．
    また，それぞれに付随するContextを保持するためのPointerがReply Targetへ格納される．

    - Callを実行し，Replyを待っている場合Source Reply ObjectにWAITが設定される．また，送信先のContextをSource Reply Targetに設定する．
    - Receiveを実行し，Reply先のContextが決定された場合Destination Reply ObjectにREADY_TO_REPLYが設定される．また，送信元のContextをDestination Reply Targetに設定する．

    Source Reply Targetは一見不要に思えるが，これは無効な参照の発生を避けるために使用される．
    仮にCallを実行した先のReceiverが途中で破棄された場合，Destination Reply Targetが無効なContextを指すことになる．したがって，Destination Reply Objectが設定されているようなContextを破棄する場合はSource Reply Targetを参照しCallを中止する必要がある．
    
    これらの構造を統合したものを(@a9n::ipc_port::call_reply_mechanism)に示す．

    #figure([
        // utility
        #let call_context(name, pos) = (node((pos), name, fill: none))
        #let receive_and_reply_context(name, pos) = (node((pos), name, fill: none))

        #diagram(
            // initialize
            node-stroke: 0.1em,
            node-fill: luma(240),
            // node-corner-radius: 0.25em,
            spacing: 4em,
            node-inset: 1em,

            call_context($"Context"_"A"$, (0, 0)),
            node((0, 0.5), "Reply (Source)"),

            receive_and_reply_context($"Context"_"B"$, (4, 0)),
            node((4, -0.5), "Reply (Destination)"),

            node((2, 0), "IPC Port"),

            edge((0, 0), (2, 0), `call`, "-|>", label-side: center, ),
            edge((4, 0), (2, 0), `receive + reply`, "-|>", label-side: center, ),

            edge((0, 0), (0, -1), (4, -1), (4, -0.5), [Configure], "..|>", label-side: center, ),
            edge((4, 0), (4, 1), (0, 1), (0, 0.5), [Configure], "..|>", label-side: center, ),

            edge((4, -0.5), (0, -0.5), (0, 0), [Copy Message], "-|>", label-side: center, label-pos: 21.5%),
            edge((0, 0.5), (4, 0.5), (4, 0), [Copy Message], "-|>", label-side: center, label-pos: 20.5%),
        )],
        caption: "Call/Reply Mechanism"
    ) <a9n::ipc_port::call_reply_mechanism>
]

#technical_term(name: `reply`)[
    Callに対してReceiveを実行した場合，先述した通りDestination Reply ObjectにREADY_TO_REPLYとCaller Contextが設定される．
    ReplyはこのDestination Reply Objectを参照してMessageを送信する．言い換えると，設定されていない場合はすぐさまReturnする．
    これも先述した通り，Receive先のContextとReply先のContextは同一であることが保証される．

    Reply Objectの存在によりIPC Portを介さない，直接的なMessageの送信が可能となる．Capability Callの仕様上IPC PortへのDescriptorを指定する必要はあるが，このIPC Portは文字通りどのIPC Portを指すものでも良い．
]

#technical_term(name: `reply_receive`)[
    Reply ReceiveはReplyとReceiveを1つのPathで実行し，高速にServerを実装するための操作である．

    典型的に，MicrokernelにおけるServerは以下のようなEvent-Driven Architectureをとる：
    + Receiveを実行し，Reply先のContextを決定する．
    + 受信したMessageを解析し，どのような処理を行うか決定する．
    + Replyを実行し，解析結果ごとの処理結果をClientに返す．
    + 1に戻る．

    疑似コードを図示すると (@a9n::ipc_port::microkernel_client_server_pseudo_code) のようになる．

    #figure(
        ```c
        void main()
        {
            message received_message;
            message reply_message;

            while (true)
            { 
                received_message = receive();

                switch(received_message.tag)
                {
                    // TAG-Specificな処理を行う
                    case TAG_A:
                        reply_message = process_tag_a(received_message);
                        break;
                    case TAG_B:
                        reply_message = process_tag_b(received_message);
                        break;
                    default:
                        return;
                }

                reply(reply_message);
            }
        }
        ```,
        caption: "Microkernelにおける典型的なServerのPseudo Code"
    ) <a9n::ipc_port::microkernel_client_server_pseudo_code>

    このうち，ReceiveとReplyは結合し，Context SwitchやCache Missのコストを削減できる．
    ただし，上記のPseudo Codeの順序をそのままに実装することはできない．A9N MicrokernelではVirtual Message RegisterをIPCの送受信ともに共通で使用するためである．
    そのため，Receive Replyのような操作として実装してしまうとReplyするためのMessageがReceiveによって上書きされてしまう．
    したがって，二者の順序を入れ替え，Replyを先に実行することでこの問題を回避する．
    すると，(@a9n::ipc_port::reply_receive_pseudo_code) で示すようなStartupを目的とするReceiveが必要である．

    #figure(
        ```c
        void main()
        {
            // あらかじめReceiveを実行しておく
            message received_message = receive();
            message reply_message;

            while (true)
            { 
                switch(received_message.tag)
                {
                    // TAG-Specificな処理を行う
                    case TAG_A:
                        reply_message = process_tag_a(received_message);
                        break;
                    case TAG_B:
                        reply_message = process_tag_b(received_message);
                        break;
                    default:
                        return;
                }

                // Loop終盤でReply Receiveを実行する
                reply_receive(reply_message);
            }
        }
        ```,
        caption: "Reply ReceiveのPseudo Code"
    ) <a9n::ipc_port::reply_receive_pseudo_code>
]

==== Direct Context Switch <ipc_port::direct_context_switch>

MicrokernelにおいてIPCは極めてCriticalな操作であり，可能な限りLow Latencyで実行する必要がある．
そのためDirect Context Switch @ElphinstoneEtAl:2013 を採用し，可能な限り#footnote[Schedulerに対象よりも高い優先度のContextが存在せず，なおかつ実行可能な場合を指す．]SenderからReceiverへ，またその逆のContextを直接Switchする．

==== Identifier <a9n::ipc_port::identifier>

同じIPC Portを共有(Copy)することでIPCは実現されるが，どのContextからMessageが送信されたかを判別するためにIdentifier機構を実装した．
IdentifierはFiasco.OCにおけるLabelやseL4におけるBadgeに相当する，Kernelによって正当性が保証されるCapability Slot固有の値である．

送信元の識別を如何に実装するかを考える．
通常のMicrokernelにおいてSenderの識別はPIDやTIDによって行われるが，A9N MicrokernelはGlobalなIDを採用していない．したがって異なるアプローチが必要である．
Kernel-LevelのPIDやTIDが存在しない場合，IPC Messageのある領域をOSが予約しIDとする実装が考えられる．しかしこれは単なるProtocolに過ぎず，各Contextは自由に改竄できるため信頼性が低い．
これを解決するのがIdentifierであり，User-Levelにおける柔軟かつSecureなContextの識別を実現する．

IPC Portに対するIdentify操作により，Word型の値をIPC Port(が格納されているSlot)に設定できる．
この値はSlot Local Data (@a9n::slot_local_data) に格納されるため，同じIPC Portを共有するContextごとに設定可能#footnote[実際にはSlot Levelで設定可能なため，各ContextがIdentifierを複数個持つこともできる．]である．
そして，この値はIPCの各操作ごとにKernelの手で転送される．

あるIPC PortのIdentifierを書き換え不可にするためには，Capability NodeのMintやDemote操作によってCapability Rights (@a9n::capability_rights) からModify Bitsを剥奪するだけでよい．この機構により，User-LevelでContextが持つIDの信頼性を保証できる．

==== Capability Transfer <a9n::ipc_port::capability_transfer>

A9N MicrokernelはIPCを通じてCapabilityを転送 (Copy) できる．

- 送信者はIPC BufferのTransfer Source Descriptors Fieldに転送したいCapability Descriptorを設定する．転送の成功時，このFieldは0にリセットされる．
- 受信者はIPC BufferのTransfer Destination Node Fieldに転送されたCapabilityを格納するNodeへのCapability Descriptorを設定し，またTransfer Destination Index Fieldに格納先NodeのIndex (Offset) を設定する．

Capability Transferは必ずIPC Bufferを介して行われるため，Virtual Message Register (@a9n::virtual_message_register) におけるHardware Registerが使用されない．したがって，Hardware Registerに格納可能なMessageのみで完結するIPCよりもやや低速である．

==== Data Structure

#technical_term(name: `message_info`)[
    IPCの細かい挙動を制御するための構造である (cf., @a9n::ipc_port::message_info)．
    送信者はこの構造を設定し，受信者は受け取ることによって情報を取得できる．
]

#figure(
    bytefield(
        bpr: 16,
        rows: (8em),
        bitheader(
            "bounds",
            0,
            8,
            15,
            text-size: 8pt,
        ),

        flag[BLOCK],
        bytes(1)[MESSAGE_LENGTH],
        bits(6)[TRANSFER_COUNT],
        flag[KERNEL],
        text-size: 4pt,
    ),
    caption: "Message Info"
) <a9n::ipc_port::message_info>

#normal_table(
    "BLOCK", "設定されている場合，IPC操作はBlockされる",
    "MESSAGE_LENGTH", "Messageの長さ (WORD_BITS単位)",
    "TRANSFER_COUNT", "TransferするCapabilityの数",
    "KERNEL", "設定されていた場合，MessageはKernelからのものであることを示す. 基本的にはFault Callのために使用され，UserがこのFlagを設定しても無視される．",
)


==== Capability Call

A9N MicrokernelにおけるIPCは第一級のKernel Callではなく，あくまでもIPC Portに対するCapability Callとして提供される．

#v(1em)

#technical_term(name: `send`)[IPC PortにMessageを送信する．]

#api_table(
    "descriptor", "ipc_port_descriptor", "対象IPC PortへのDescriptor",
    "message_info", "info", [送信するMessageの情報 \ (cf., @a9n::ipc_port::message_info)],
)

#technical_term(name: `receive`)[IPC PortからMessageを受信する．]

#figure(
    api_table(
        "descriptor", "ipc_port_descriptor", "対象IPC PortへのDescriptor",
    ),
    caption: [`receive`の引数]
)

#figure(
    api_table(
        "message_info", "info", [受信したMessageの情報 \ (cf., @a9n::ipc_port::message_info)],
        "word", "identifer", "送信元のIdentifier",
        "word[n]", "messages", "受信したMessage",
    ),
    caption: [`receive`の戻り値]
)

#technical_term(name: `call`)[IPC Portに対してCallを実行する．]

#figure(
    api_table(
        "descriptor", "ipc_port_descriptor", "対象IPC PortへのDescriptor",
        "message_info", "info", [送信するMessageの情報 \ (cf., @a9n::ipc_port::message_info)],
    ),
    caption: [`call`の引数]
)

#figure(
    api_table(
        "message_info", "info", [受信したMessageの情報 \ (cf., @a9n::ipc_port::message_info)],
        "word", "identifer", "送信元のIdentifier",
        "word[n]", "messages", "受信したMessage",
    ),
    caption: [`call`の戻り値]
)

#technical_term(name: `reply`)[IPC Portに対してReplyを実行する．]

#api_table(
    "descriptor", "ipc_port_descriptor", [対象IPC PortへのDescriptor#footnote[前述したように，Reply時に指定するIPC PortはどのIPC Portでも機能する．]],
    "message_info", "info", [送信 (Reply) するMessageの \ 情報 (cf., @a9n::ipc_port::message_info)]
)

#technical_term(name: `reply_receive`)[IPC Portに対してReply Receiveを実行する．]

#figure(
    api_table(
        "descriptor", "ipc_port_descriptor", [対象IPC PortへのDescriptor],
        "message_info", "info", [送信 (Reply) するMessageの \ 情報 (cf., @a9n::ipc_port::message_info)],
    ),
    caption: [`reply_receive`の引数]
)

#figure(
    api_table(
        "message_info", "info", [受信したMessageの情報 \ (cf., @a9n::ipc_port::message_info)],
        "word", "identifer", "送信元 (Caller) のIdentifier",
        "word[n]", "messages", "受信したMessage",
    ),
    caption: [`reply_receive`の戻り値]
)

#technical_term(name: `identify`)[IPC Portに対してSlot-LocalなIdentifierを設定する．]

#api_table(
    "descriptor", "ipc_port_descriptor", "対象IPC PortへのDescriptor",
    "word", "identifier", "IPC Portに付与するIdentifier",
)

#pagebreak()

=== Notification Port Capability

Notification PortはAsynchronous Notificationを実現するためのCapabilityである．
Notification PortはIPC Portとは異なり，1WordのNotification Flag Fieldのみを持つ．

==== Identifier

IPC PortのIdentifier (cf., @a9n::ipc_port::identifier) と同じIdentifier機構を持つ．

==== Capability Call

#technical_term(name: `notify`)[
    Notification Portに対してNotificationを送信する．Slot-LocalなIdentifierはNotification Flag FieldにBitwise ORされる．
]

#api_table(
    "descriptor", "notification_port_descriptor", "対象Notification PortへのDescriptor"
)

#technical_term(name: `wait`)[
    Notification Portに対してNotificationが発生するまでBlockする．
    Notificationが発生した場合IdentiferがBitwise ORされたNotification Flag Fieldが返され，その後Fieldは0にリセットされる．
]

#figure(
    api_table(
        "descriptor", "notification_port_descriptor", "対象Notification PortへのDescriptor"
    ),
    caption: [`wait`の引数]
)

#figure(
    api_table(
        "message_info", "info", "受信したMessageの情報",
        "word", "flag", "Notification PortのFlag Field",
    ),
    caption: [`wait`の戻り値]
)

#technical_term(name: `poll`)[
    Notification PortのNotificationをNon-Blockingで取得する．
    Identifierが設定されていない場合のNotificationも対象となる#footnote[Identiferが設定されていない場合，対象となるIdentifierは自動的に0として扱われる．この状態でBitwise ORをしてもFlag Fieldは変化しないが，Notificationが発生したという情報はそのまま伝達される．]．
]

#figure(
    api_table(
        "descriptor", "notification_port_descriptor", "対象Notification PortへのDescriptor"
    ),
    caption: [`poll`の引数]
)

#figure(
    api_table(
        "message_info", "info", "受信したMessageの情報",
        "word", "flag", "Notification PortのFlag Field",
    ),
    caption: [`poll`の戻り値]
)

#technical_term(name: `identify`)[Notification Portに対してSlot-LocalなIdentifierを設定する．]

#api_table(
    "descriptor", "notification_port_descriptor", "対象Notification PortへのDescriptor",
    "word", "identifier", "IPC Portに付与するIdentifier"
)

#pagebreak()

=== Interrupt Region Capability

Interrupt Regionは割り込みを抽象化するInterrupt Portを生成する (cf., @a9n::interrupt_region::make_port::example) ためのCapabilityである．
このCapabilityはGenericからConvertできず，Init Serverの起動時にInit Protocolを通じて1つだけ生成される．
Genericを介さないためMemory Regionを消費することはない．

#figure(block(inset: 1em)[
    #diagram(
        // initialize
        node-stroke: 0.1em,
        // node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: 4em,
        node-inset: 1em,

        // draw nodes
        node((0, 0), [$"InterruptRegion"_"Root"$], name: <interrupt_region>),
        node((2, 0), [$"InterruptPort"_"0"$], name: <interrupt_port::0>),
        node((2, 0.5), [$"InterruptPort"_"1"$], name: <interrupt_port::1>),
        node((2, 1), [$"InterruptPort"_"2"$], name: <interrupt_port::2>),
        node((2, 1.5), [$"InterruptPort"_"n"$], name: <interrupt_port::n>),

        edge(<interrupt_region>, (1, 0), (1, 0.5), <interrupt_port::1>, "-|>", label-side: center),
        edge(<interrupt_region>, (1, 0), (1, 1), <interrupt_port::2>, "-|>", label-side: center),
        edge(<interrupt_region>, (1, 0), (1, 1.5), <interrupt_port::n>, "-|>", label-side: center),

        // overwrite
        edge(<interrupt_region>, <interrupt_port::0>, `make_port`, "-|>", label-side: center),
    ),
    ],
    caption: "Interrupt RegionからInterrupt Portを生成する例"
) <a9n::interrupt_region::make_port::example>

==== Capability Call

#technical_term(name: `make_port`)[
    Interrupt RegionからInterrupt Portを生成する．
    この操作によって生成されるInterrupt PortはIRQ Numberごとに一意である．
]

#api_table(
    "descriptor", "interrupt_region_descriptor", "対象Interrupt RegionへのDescriptor",
    "word", "irq_number", "生成するInterrupt PortのIRQ Number",
    "capability_descriptor", "node_descriptor", "Interrupt Portを格納するNodeへのDescriptor",
    "word", "index", "Interrupt Portを格納するNodeのIndex (Offset)",
)

#pagebreak()

=== Interrupt Port Capability

Interrupt PortはInterrupt Regionから生成されるCapabilityである．
特定のIRQ Numberと1:1で対応しており，割り込み発生時に指定したNotification PortへNotificationを送信する (cf., @a9n::interrupt_port::interrupt::example)．

#figure(block(inset: 1em)[
    #diagram(
        // initialize
        node-stroke: 0.1em,
        // node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: (6em, 2em),
        node-inset: 1em,

        // draw nodes
        node((0, 0), [Interrupt], name: <interrupt>, shape: circle, extrude: (-3, 0), inset: 1.5em, fill: luma(240)),
        node((1, 0), [$"InterruptPort"_"n"$], name: <interrupt_port::0>),
        node((2, 0), [$"NotificationPort"_"A"$], name: <notification_port::a>),

        edge(<interrupt>, <interrupt_port::0>, "-|>", "wave", label-side: center),
        edge(<interrupt_port::0>, <notification_port::a>, "-|>", [`notify`], label-side: center),
        edge(<notification_port::a>, (2, -1), (1, -1), <interrupt_port::0>, "-|>", [`bind`], label-side: center),
        edge(<interrupt_port::0>, (1, 1), (2, 1), <notification_port::a>, "<>-|>", [`has-a`], label-side: center),
    )
    ],
    caption: "Interrupt PortからNotification PortへのNotificationを送信する例"
) <a9n::interrupt_port::interrupt::example>

==== Capability Call

#technical_term(name: `bind`)[
    Interrupt PortにNotification PortをBindする．
    割り込み発生時，このNotification PortへNotificationが送信される．
]

#api_table(
    "capability_descriptor", "interrupt_port", "対象Interrupt PortへのDescriptor",
    "capability_descriptor", "notification_port", "BindするNotification PortへのDescriptor",
)

#technical_term(name: `unbind`)[
    Interrupt PortにBindされているNotification PortをUnbindする．
]

#api_table(
    "capability_descriptor", "interrupt_port", "対象Interrupt PortへのDescriptor",
)

#technical_term(name: `ack`)[
    Interrupt Portに対して割り込みをAckする．この操作によって割り込みを再度有効化する．
]

#api_table(
    "capability_descriptor", "interrupt_port", "対象Interrupt PortへのDescriptor",
)

#technical_term(name: `get_irq_number`)[
    Interrupt Portが対応するIRQ Numberを取得する．
]

#figure(
    api_table(
        "capability_descriptor", "interrupt_port", "対象Interrupt PortへのDescriptor",
    ),
    caption: [`get_irq_number`の引数]
)

#figure(
    api_table(
        "word", "irq_number", "Interrupt Portが対応するIRQ Number",
    ),
    caption: [`get_irq_number`の戻り値]
)

#pagebreak()

=== IO Port Capability

IO PortはPort-Mapped IO (i.e., PMIO) を抽象化するCapabilityである．
PMIOの存在はArchitectureに依存する．したがって，PMIOが存在しないArchitectureにおいて読み書き操作は無視される．
IO PortもInterrupt Portと同様にGenericからConvertできず，Init Serverの起動時にInit Protocolを通じて1つだけ生成される．
また，Genericを介さないためMemory Regionを消費しない．

==== Region

IO PortはIO Address Regionを持ち，この範囲のAddressに対してのみ読み書き操作が可能である．
また，IO Portは自身のSubsetであるIO PortをMint操作によって生成することができる (cf., @a9n::io_port::mint::example)．これにより，特定のAddressに対してのみ読み書き操作を許可することができ，特権の最小化を実現する．

#figure([
    #diagram(
        // initialize
        node-stroke: 0.1em,
        // node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: 2em,
        node-inset: 1em,

        node((0, 0), [$"IOPort"_"A"$ \[0x0000 - 0xFFFF)], name: <ioport_a>),
        node((-0.75, 1), [$"IOPort"_"B"$ \[0x0000 - 0x9000)], name: <ioport_b>),
        node((0.75, 1), [$"IOPort"_"C"$ \[0x9000 - 0xFFFF)], name: <ioport_c>),
        node((-1.5, 2), [$"IOPort"_"D"$ \[0x0000 - 0x6000)], name: <ioport_d>),
        node((-0.25, 2), [$"IOPort"_"E"$ \[0x3000 - 0x4000)], name: <ioport_e>),

        edge(<ioport_a>, <ioport_b>, [Mint], "-|>", label-side: center, label-pos: 40%, label-anchor: "north"),
        edge(<ioport_a>, <ioport_c>, [Mint], "-|>", label-side: center, label-pos: 40%, label-anchor: "north"),
        edge(<ioport_b>, <ioport_d>, [Mint], "-|>", label-side: center, label-pos: 40%, label-anchor: "north"),
        edge(<ioport_b>, <ioport_e>, [Mint], "-|>", label-side: center, label-pos: 40%, label-anchor: "north"),
    )],
    caption: "MintによるIO PortのSubset生成例"
) <a9n::io_port::mint::example>

==== Capability Call

#technical_term(name: `read`)[
    IO Portから値をReadする．
]

#figure(
    api_table(
        "capability_descriptor", "io_port_descriptor", "対象IO PortへのDescriptor",
    ),
    caption: [`read`の引数]
)

#figure(
    api_table(
        "word", "data", "IO PortからReadした値",
    ),
    caption: [`read`の戻り値]
)

#technical_term(name: `write`)[
    IO Portに値をWriteする．
]

#api_table(
    "capability_descriptor", "io_port_descriptor", "対象IO PortへのDescriptor",
    "word", "data", "IO PortにWriteする値",
)

#technical_term(name: `mint`)[
    IO PortのSubsetを生成する．
]

#api_table(
    "capability_descriptor", "io_port_descriptor", "対象IO PortへのDescriptor",
    "word", "new_address_min", "生成するSubsetの最低Address",
    "word", "new_address_max", "生成するSubsetの最高Address",
    "capability_descriptor", "node_descriptor", "生成したSubsetを格納するNodeへのDescriptor",
    "word", "index", "生成したSubsetを格納するNodeのIndex (Offset)",
)

#pagebreak()

=== Virtual CPU Capability

TODO

#pagebreak()

=== Virtual Address Space Capability

TODO

#pagebreak()

=== Virtual Page Table Capability

TODO

#pagebreak()

=== ABI <a9n::abi>

A9N MicrokernelのHALはArchitectureごとにKernel ABIを定義する．
ここでいうABIは，主にKernel CallとVirtual Message RegisterにおけるHardware RegisterのMappingを指す．

==== Hardware-Independent ABI Constants

Kernel Call Typeは全てのABIにおける共通値が以下として定義される (cf., @a9n::abi::hardware_independent_constants)：

#figure(
    api_table(
        "sword", "Capability Call", "-1",
        "sword", "Yield Call", "-2",
        "sword", "Debug Call", "-3",
    ),
    caption: "Kernel Call Type"
) <a9n::abi::hardware_independent_constants>

通常のSystemにおけるKernel Call TypeはSystem Call Numberとして知られるが，A9N Microkernelではこの値を負数として定義する．
Kernel Call時に存在しないKernel Call Typeの値を指定するとIllegal Kernel Call Faultが発生する．したがって，ABI-LevelのKernel Call (System Call) Emulationが実現しやすくなる．

==== x86_64 <a9n::abi::x86_64>

x86_64におけるKernel CallのABIは以下のように定義される (cf., @a9n::abi::x86_64::kernel_call)：

#figure(
    normal_table(
        "Kernel Call Type", "Mapped to RDI",
        "Reserved", "Mapped to RAX （破壊される）"
    ),
    caption: "x86_64におけるKernel Call ABI"
)<a9n::abi::x86_64::kernel_call>


また，Virtual Message RegisterのABIは以下のように定義される (cf., @a9n::abi::x86_64::virtual_message_register)：

#figure(
    normal_table(
        "Message Register [0]", "Mapped to RSI",
        "Message Register [1]", "Mapped to RDX",
        "Message Register [2]", "Mapped to R8",
        "Message Register [3]", "Mapped to R9",
        "Message Register [4]", "Mapped to R10",
        "Message Register [5]", "Mapped to R12",
        "Message Register [6]", "Mapped to R13",
        "Message Register [7]", "Mapped to R14",
        "Message Register [8]", "Mapped to R15",
    ),
    caption: "x86_64におけるVirtual Message Register ABI"
) <a9n::abi::x86_64::virtual_message_register>

これを超えるMessage Register (e.g., Message Register [$"n", n in NN, n > 8 $]) はIPC BufferのMessage Field [$n$] にMappingされる．

#pagebreak()

=== Boot Protocol <a9n::boot_protocol>

A9N MicrokernelはA9N Boot ProtocolをもってBootする必要があり，この根幹をなすのがBoot Infoである．
Boot InfoはKernelの起動に必要な情報を格納する構造体であり，以下のように定義される (cf., @a9n::boot_protocol::boot_info)：

#figure(
    ```cpp
    static constexpr a9n::word ARCH_INFO_MAX = 8;

    struct boot_info
    {
        memory_info     boot_memory_info;
        init_image_info boot_init_image_info;
        a9n::word       arch_info[ARCH_INFO_MAX];
    } __attribute__((packed));

    ```,
    caption: "A9N Boot Info"
) <a9n::boot_protocol::boot_info>

#technical_term(name: `memory_info`)[
    Memory Info(@a9n::boot_protocol::memory_info) はKernelに利用可能なPhysical Memory Regionを伝達するための構造である．
    Kernelの起動前にメモリ領域の開始Address, Page SizeをUnitとするPage Count, およびMemory Typeを収集し格納する必要がある．
    Kernelはこの情報をもとにGenericを生成し，後述するInit Info (@a9n::init_protocol::init_info) へ情報を再格納してUserに委譲する．
]

#figure(
    ```cpp
    enum class memory_map_type
    {
        FREE,
        DEVICE,
        RESERVED,
    };
    struct memory_map_entry
    {
        a9n::physical_address start_physical_address;
        a9n::word             page_count;
        memory_map_type       type;
    };
    struct memory_info
    {
        a9n::word         memory_size;
        uint16_t          memory_map_count;
        memory_map_entry *memory_map;
    };
    ```,
    caption: "A9N Boot InfoにおけるMemory Info"
) <a9n::boot_protocol::memory_info>

#technical_term(name: `init_image_info`)[
    A9N MicrokernelはELFやPEといった特定のExecutable Formatに依存しない．したがって，Kernelが起動する前のBootloader PhaseにおいてInit Serverを適切に展開しLoadする必要がある．
    そのようにしてLoadされたInit Serverの情報はInit Image Info (cf., @a9n::boot_protocol::init_image_info) に格納されKernelに渡される．
]

#figure(
    ```cpp
    struct init_image_info
    {
        a9n::physical_address loaded_address;
        a9n::word             init_image_size;
        a9n::virtual_address  entry_point_address;
        a9n::virtual_address  init_info_address;
        a9n::virtual_address  init_ipc_buffer_address;
    } __attribute__((packed));
    ```,
    caption: "A9N Boot InfoにおけるInit Image Info"
) <a9n::boot_protocol::init_image_info>

#technical_term(name: `arch_info`)[
    Architecture InfoはArchitecture-SpecificなFieldであり，主にHALの起動に使用される．
    また，殆どの場合Init Info (@a9n::init_protocol::init_info) の同名Fieldへ再格納される．
]

==== x86_64

x86_64におけるBoot InfoのArchitecture Infoは以下のように定義される．現在はたった一つのFieldのみが使用されており，残りは将来の拡張用に予約されている (cf., @a9n::boot_protocol::x86_64::arch_info)：

#figure(
    normal_table(
        "Architecture Info[0]", [RSDP#footnote[ACPIにおけるRSDP:Root System Description PointerのPhysical Address．]],
    ),
    caption: "x86_64におけるArchitecture Info"
) <a9n::boot_protocol::x86_64::arch_info>

現在のA9N (x86_64)はEDK2-BasedのA9NLoaderによってUEFI環境上でBootされるため，RSDPはA9NLoaderがUEFIの手続きに従って取得する．

==== Jump to Kernel

Boot Info (cf., @a9n::boot_protocol::boot_info) はKernel Main Entry Pointへの引数として渡される必要がある．
Kernel Main Entry Pointは以下のように定義される (cf., @a9n::boot_protocol::kernel_entry)：

#figure(
    ```cpp
    extern "C" int kernel_entry(a9n::kernel::boot_info *target_boot_info);
    ```,
    caption: "Kernel Main Entry Point"
) <a9n::boot_protocol::kernel_entry>

このEntry PointはArchitectureに依存しないものである．したがって，典型的なKernelの起動は以下のPhaseによって行われる (cf., @a9n::boot_protocol::kernel_boot_sequence)：

#figure([
    #diagram(
        // initialize
        node-stroke: 0.1em,
        // node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: (4em, 1em),
        node-inset: 1em,

        // draw nodes
        // boot
        node((0, 1), [$"Startup"$], name: <startup>, shape: circle, extrude: (-3, 0), fill: luma(240)),
        node((1, 1), [$"Bootloader"$], name: <bootloader>),

        // kernel
        node((3, 0), [$"A9N::HAL"$], name: <a9n::hal>),
        node((3, 2), [$"A9N::Kernel"$], name: <a9n::kernel>),
        node(enclose: (<a9n::hal>, <a9n::kernel>), name: <a9n>),

        // user
        node((5, 1), [$"Init Server"$], name: <init_server>),

        edge(<startup>, <bootloader>, "-|>", label-side: center),
        edge(<bootloader>, <a9n>, "-|>", [Load], label-side: center),
        edge(<bootloader>, (1, 0), <a9n::hal>, "-|>", [Jump], label-side: center, label-pos: 75%),
        edge(<bootloader>, (1, 4), (5, 4), <init_server>, "-|>", [Load], label-side: center),
        edge(<a9n::hal>, <a9n::kernel>, "-|>", [Jump to Entry], label-side: center),
        edge(<a9n>, <init_server>, "-|>", [Jump], label-side: center),
    )
    ],
    caption: "Kernel Boot Sequence"
) <a9n::boot_protocol::kernel_boot_sequence>

#pagebreak()

=== Init Protocol <a9n::init_protocol>

A9N MicrokernelはInit ServerをBoot Infoの情報をもとに生成し起動する．
Init Serverに利用可能なCapabilityや初期状態を提供するため，Init Info構造体 (cf., @a9n::init_protocol::init_info) が使用される．

#figure(
    ```cpp
    test
    ```,
    caption: "A9N Init Info"
) <a9n::init_protocol::init_info>

#pagebreak()

== Nun Operating System Frameworkの開発

=== Build System <nun::build_system>

=== HAL <nun::hal>

=== Entry Point <nun::entry_point>

=== API <nun::api>

/* ===== KOITO ===== */

#pagebreak()

== KOITOの開発

=== Standard C Library

// CMake Integration

=== Memory Management Server

=== POSIX Server

#pagebreak()

/* ===== liba9n ===== */

== `liba9n`の開発

=== `liba9n::std`

=== `liba9n::option<T>`

=== `liba9n::result<T, E>`

=== Monadic Operation

=== Conditionally Trivial Special Member Functions

=== `liba9n::not_null<T>`

#pagebreak()

/* ===== A9NLoader ===== */

== A9NLoaderの開発

=== Init ServerのLoad

=== ELF Symbolの解決

=== CMake Integration
