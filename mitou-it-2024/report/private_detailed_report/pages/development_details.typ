#import "/components/api_table.typ" : *
#import "@preview/bytefield:0.0.7": *
#import "@preview/cetz:0.3.2"

#import "/components/term.typ" : *

= 開発内容

/* ===== A9N ===== */

== A9N Microkernelの開発

=== Basic Types

A9N MicrokernelはC++20を用いて開発されているが，Kernel内部で広範に使用するための基本型を定義している．
Kernel内部では幅が固定された型を基本的に使用せずに`word`型を使用する．
`word`はArchitecture-SpecificなWord幅を持つ符号なし整数型であり，`uintmax_t`のAliasとして定義される．
これにより，速度と移植容易性を実現する．

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
#v(1em)

すべてのCapabilityはCapability Componentの実装である．

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

Capability Rightsには，先天的に設定されるものと後天的に設定するものの両方が存在する．
原則として，Capabilityは作成時点にすべてのRights Bitが設定される．
ただし，Copyを許可すると同一性が失われてしまうようなCapabilityはCopyが最初から禁止される．

=== Dependency Node

Capabilityはその依存関係をDependency Node (@dependency_node) によって管理する．
Dependency Nodeは依存関係にあるCapability Slotを保持するが，`depth`によって子と兄弟を区別する．

#v(1em)
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

=== Capability Node

Capability NodeはCapabilityを格納するためのCapabilityであり，seL4 MicrokernelにおけるCNodeの設計をベースとしている．
1つのNodeは$2^"radix_bits"$個のCapability Slotを持ち．この数だけCapabilityを格納できる．
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

#v(1em)
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
#v(1em)

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

#v(1em)
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
#v(1em)

ここで, $"Capability"_"Target"$を対象としてCapability Callを実行したい場合を考えると，Capability Descriptorは (@capability_target_descriptor) のようになる#footnote()[簡略化のために32bit ArchitectureにおけるDescriptorを例示しているが，異なるWord幅のArchitectureにおいても同様の構造をとる．]:

//   0001 1000 = 0x24 (depth)
//   0000 0011 = 0x02 (node_0)
// 000000 0011 = 0x03 (node_1)
//     00 0101 = 0x04 (node_2)
#text()[$
    "descriptor"        &:= &"0x"&"180300C5" &("hex") \ 
                        &:= &"0b"&"00011000000000110000000011000101" &("bin")
$] <capability_target_descriptor>
// 00011000'00000011'00000000'11000101

これをNodeのRadix Bitsによってパースすると，(@parsed_capability_target_descriptor) となる:

$
    0b
    overbracket(underbracket(00011000, "Depth"), "8bit")
    overbracket(underbracket(00000011, "Index"_("Node"_0)), "8bit")
    overbracket(underbracket(0000000011, "Index"_("Node"_1)), "10bit")
    overbracket(underbracket(00101, "Index"_("Node"_2)), "6bit")
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
    "descriptor"        &:= &"0x"&"803xxxx" &("hex") \ 
                        &:= &"0b"&"0000100000000011 xxxxxxxxxxxxxxxx" &("bin")
$] <capability_node_1_descriptor>

これをNodeのRadix Bitsによってパースすると，(@parsed_node_1_descriptor) となる:

$
    0b
    overbracket(underbracket(00001000, "Depth"), "8bit")
    overbracket(underbracket(00000011, "Index"_("Node"_0)), "8bit")
    overbracket(underbracket("XXXXXXXXXXXXXXXX", "Unused"), "remain bits")
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

#technical_term(name: `demote`)[CapabilityのRightsを不可逆的に降格する．新しいRightsは元となるRightsのSubsetである必要がある．]

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
- Size Radix BitsはGenericが指すMemory RegionのSizeを示す．$2^"size_radix_bits"$が実際のSizeを表す．この事実から分かるように，GenericのSizeは必ず2の累乗byteである．
- WatermarkはGenericの使用状況を示すPhysical Addressである．
- Device BitsはMemory RegionがDeviceのために使用されるような場合(e.g., MMIO)に設定される．

Generic CapabilityはすべてのCapabilityを作成するためのFactoryとして機能する．
Convert操作 (@generic::convert) によってGeneric Capabilityの領域を消費し，新たなCapabilityを生成することができる．
作成したCapabilityはDependency Nodeへ子として設定され，破棄の再帰的な実行に利用される．

=== Capability Call

#technical_term(name: `convert`)[Generic Capabilityの領域を指定されたCapability Typeに変換する．]

#figure(
    api_table(
        "capability_descriptor", "generic_descriptor", "対象GenericへのDescriptor",
        "capability_type", "type", "作成するCapabilityのType",
        "word", "specific_bits", [Capability作成時に使用する固有Bits \ cf., @generic::specific_bits],
        "word", "count", "作成するCapabilityの個数",
        "capability_descriptor", "node_descriptor", "格納先NodeへのDescriptor",
        "word", "node_index", "格納先NodeのIndex",
    ),
    caption: "GenericのConvert操作",
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
