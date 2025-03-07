/* ===== global settings ===== */
// page settings 
#set page(
    paper: "a4",
    margin: (x: 25mm, y: 25mm),
    /*
    footer: context {
        let page_number = counter(page).at(here()).first()
        align(center, [#page_number])
    },
    */
    numbering: "1/1",
)

#show heading: it => {
    text(size: 12pt, weight: "bold")[#it]
    v(0.5em)
}

#set par(
    first-line-indent: (amount: 1em, all: true),
)

/*
Apple LiGothic
Apple SD Gothic Neo
Apple SD Gothic NeoI
AppleGothic
BokutachinoGothic2Bold
Hiragino Kaku Gothic Interface
Hiragino Kaku Gothic Pro
Hiragino Kaku Gothic ProN
Hiragino Kaku Gothic Std
Hiragino Kaku Gothic StdN
Hiragino Maru Gothic Pro
Hiragino Maru Gothic ProN
MS Gothic
MS PGothic
MS UI Gothic
Nagomi Gokuboso Gothic
NanumGothic
Noto Sans Gothic
Toppan Bunkyu Gothic
Toppan Bunkyu Midashi Gothic
Tsukushi A Round Gothic
Tsukushi B Round Gothic
YuGothic
Noto Sans JP,
Zen Kaku Gothic New
*/

// text
#set text(
    font: "Zen Kaku Gothic New",
    size: 12pt,
)

#set strong(delta: 100)
#show strong: set text(weight: "medium")

#let title(project_name: [Revue Starlight], subtitle: [あなたをスタァライトしちゃいます！]) = {
    align(center, 
        block[
            #text(14pt)[#project_name]
            #v(0.5em)
            #text(14pt)[$dash.em.two$ #subtitle $dash.em.two$]
            #v(0.5em)
        ]
    )
}

#title(
    project_name: [
        Capability-Based Microkernelによる \ セキュアなユーザレベルメモリ管理システム
    ],
    subtitle: [
        最速の3rd-Generation Microkernelとその応用
    ]
)

#import "@preview/cetz:0.3.2"
#import "@preview/fletcher:0.5.5" as fletcher: diagram, node, edge

== 1．背景
近年，計算機の民主化による*Internet of Things（IoT）*の拡大は大きなムーブメントを生み出している．Moore's Lawで予見されたように，半導体集積回路に対する面積当たりのトランジスタ数は指数関数的に増加した． このようなHardwareの技術革新により，かつては軍事や研究機関に限られていた高度な計算資源が一般にも普及し利用されるようになった． そして，これらは相互にNetworkを形成し，*Ubiquitous Computing*の実現に向け進化を遂げつつある．
これにより，HardwareとUserを繋ぐ基盤となる*Kernel*や*OS*といったSoftwareの役割もますます重要視されるように変化している．

しかし，Linuxのように*Monolithic*な構造を持つKernelはもはや現代の要求に適合しなくなりつつある． このようなArchitectureはProject成長に伴うCode Baseの肥大化が避けられず，*Trusted Computing Base*（TCB）の拡大によるSecurity上のリスクが増大する． また，人的リソースの限界による開発の困難化や，利害関係者の増加に伴う意思決定スピードの低下も問題となる．

Kernelを柔軟かつ安定したものとするため，*Microkernel*というArchitectureが存在する．MicrokernelはMonolithic Kernelとは異なり，提供する機構を最小化することでUserへ最小限の*Application Programming Interface（API）*のみを提供するような設計手法である．したがって，ほぼ全てのSystem ComponentはUser-Levelで実行され．安定性と柔軟性を両立させることができる．
また，User-Levelで実行されるそれぞれのComponentは互いに*Inter Process Communication（IPC）*し，ある種のNetworkを形成する．そのため，Ubiquitous Computingのような相互通信を基本とするSystemにも適する．

ただし，Microkernelは性能面の問題を抱えている．Microkernelはその特性上，IPCの実行回数がMonolithic Kernelと比較しても増加しOverheadとなる． また，多くのMicrokernelはSecurity上の問題からMemory ManagementをKernel-Levelで実行する傾向にあり，Microkernelの持つ利点が損なわれてしまう問題がある．

#v(0.5em)

== 2．目的

MonolithicなKernelやMicrokernelの問題を解決するためには，柔軟性と安定性，安全性，そして性能を両立させる必要がある．そのため，本Projectではこれらの要求を満たす新たなKernelと，そのKernelをBaseとしたSystemの開発を実施した．

#v(0.5em)

== 3．開発の内容

本Projectでは，*Object-Capability Model*による*3rd-Generation Capability-Based Microkernel*である*A9N Microkernel*を開発した．また，このKernelをBaseとしてOSを構築するためのFrameworkである*Nun*と，それを用いて実装される，User-LevelでMemory Managementを実行するOSである*KOITO*を開発した．加えて，A9N MicrokernelをModernに開発するためのLibraryである*`liba9n`*も開発した．

#figure(
    diagram(
        // initialize
        node-stroke: 0.1em,
        // node-fill: luma(240),
        // node-corner-radius: 0.25em,
        spacing: (1em, 1em),
        node-inset: 1em,

        // draw nodes
        node((0, -1),  [Application], name: <application>),
        node((0, 1),  [KOITO Server], name: <koito_server>),
        node((-1, 1),  [POSIX Server], name: <posix_server>),
        node((1, 1),  [ULMM Server], name: <ulmm_server>),
        node((0, 2), [Nun], name: <nun>),
        node(
            enclose: (
                <koito_server>,
                <posix_server>,
                <ulmm_server>,
                <nun>
            ),
            name: <koito>
        ),
        node(
            enclose: (
                <application>,
                <koito_server>,
                <posix_server>,
                <ulmm_server>,
                <nun>
            ),
            name: <user>,
            inset: 2em
        ),

        node((0, 5), [A9N Microkernel], name: <a9n>, fill: luma(240)),
        node((1, 5), [`liba9n`], name: <liba9n>),

        /*
        edge(<application>, <koito_server>, "<|-|>", label-side: center),
        edge(<application>, <posix_server>, "<|-|>", label-side: center),
        edge(<application>, <ulmm_server>, "<|-|>", label-side: center),
        */
        edge(<application>, <koito>, "-|>", label-side: center),
        edge(<koito_server>, <posix_server>, "<|-|>", label-side: center),
        edge(<koito_server>, <ulmm_server>, "<|-|>", label-side: center),
        edge(<koito_server>, <nun>, "-", label-side: center),

        edge(<koito>, <a9n>, "-|>", label-side: center, label-pos: 20%),
        edge(<a9n>, <liba9n>, "-", label-side: center),
    ),
    caption: "Project Architecture",
) <project::architecture>

#v(0.5em)

A9N MicrokernelはCapabilityという概念を用いることで，柔軟かつ安全にSystemを構築できる．CapabilityはあるObjectに対する操作権限を表す譲渡可能かつ偽造不可能なTokenであり，Userはこれを用いることでのみ特権的なObjectに対する操作を実行できる．従来のAccess Control List（ACL）とは異なり，Capabilityそのものが操作に必要な鍵といえる．
これにより，A9N Microkernelが持つKernel-Level APIは極めて簡素化され，種類としてはCapabilityに対して操作を実行する*Capability Call*と，実行中ContextがTime Sliceを譲る*Yield Call*，そしてDebugに使用される*Debug Call*の3つのみになる．

それぞれのCapabilityは*Radix-Based Capability Node*によって管理され，Addressingされる．そのため，探索にかかる時間はわずか$"O"(log "n")$であり，極めて高速である．

Memoryに関連する特権的操作として，*Generic Capability*，*Address Space Capability*，*Page Table Capability*，そして*Frame Capability*などが提供される．これによりA9N MicrokernelはKernel内にHeapを持たず，完全にUser-LevelでMemory Managementを実現する．また，これらの操作はArchitecture-Independentであり，Userは実装したMemory Management Serverを容易にPortingできる．

また，A9N Microkernelは高速なIPC機構を持つ．*Virtual Message Register*によってHardware Registerを効率的に利用し，Low-LatencyなIPCを実現する．さらに，Client-Server Modelに最適化された*Call*と*Reply Receive*が*Send*や*Receive*といった基本的な機構に置き換わり使用される（cf., @ipc::call_reply_mechanism）．この機構により，IPCのさらなる高速化を実現する．

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
) <ipc::call_reply_mechanism>

#v(0.5em)

NunはA9N Microkernel上にOSを構築するためのRust製Frameworkである．KernelはInit ProtocolをもってInitial Serverを起動するが，このFrameworkはそのProtocolに沿うOSを構築するために最小限の抽象化を提供する．Rustを用いることでType SafetyやMemory Safetyを保証し，またCargoによる優れたBuild Systemを享受できる．
通常，Microkernel-Based SystemのStartupは複雑な処理Flowを持つが，Nunはこれを簡略化し，UserがOSを開発する際の負担を軽減する．

#v(0.5em)

KOITOはNunによって実装される，A9N Microkernel上で動作するOSである．A9Nによって提供されるMechanismを用い，それに対応するPolicyを実装するLayerといえる．実態としては複数のServerで実現される抽象概念であり，Initial Server, POSIX Compatible Server, User-Level Memory Management Serverによって構成される．
KOITOを構成する各ServerはすべてUser-Levelで動作するため，極端なUsecaseから普遍的なUsecaseまで動的かつ柔軟に対応することが可能となる．

#v(0.5em)

`liba9n`はA9N Microkernelのために設計されたC++20用のTemplate Libraryであり，Monadic Operationを用いたModernなError Handling機構を提供する．．Standard Libraryに一切依存しないため，EmbeddedなFreestanding環境やA9N Microkernel以外のProjectでも使用できる．

#v(0.5em)

== 4．従来の技術との相違

既存のCapability-Based MicrokernelはArchitecture-DependentなAPIを持つことが多く，User-Level ServerのPortingが困難であることが多い． 一方，A9N MicrokernelはHardware Abstraction Layerを備えることでKernel-LevelのPortabilityを実現し，さらにArchitecture-IndependentなAPIを提供することによるUser-LevelのPortabilityも実現している．また，A9N Microkernelは極めて高速なIPC機構を持ち，NICTAの開発したseL4，Kernkonzeptの開発したFiasco.OC, Googleの開発したZirconといった競合となる3rd-Generation Microkernelと比較したBenchmark（cf., @ipc::benchmark）の結果，590Cycles/91.4nsというx86_64 Architectureにおいてほぼ世界最速といえる値を達成した．そのため，このKernelは柔軟性，安定性，安全性，性能，さらにPortabilityを兼ね備えたものといえる．また，Rust-BasedなOS構築を支援するFrameworkの実装も他にはあまり見られない．

#figure(
    table(
      columns: (1fr, 1.5fr, 1fr),
      inset: 8pt,
      align: (left, left, right),
      fill: (x, y) =>
          if y == 0 {
                luma(240)
          },
      table.header(
        [*Kernel*], [*Architecture*], [*Cycles*],
      ),
      [seL4 (Fastpath)], [Intel® Core™ i7-6700], [786], 
      [Fiasco.OC (Fastpath)], [Intel® Core™ i7-6700K], [2717],
      [Zircon], [Intel® Core™ i7-6700K], [8157],
      [A9N], [Intel® N150], [590], 
    ),
    caption: [Single-Core IPC Round-Trip Latency cf., @ZeyuMiEtAl:2019, @seL4Performance:2022],
) <ipc::benchmark>

#v(0.5em)

== 5．期待される効果

本ProjectはあらゆるUsecaseに対応することが可能な抽象性を持っている．そのため，Embedded DeviceからServer，HPC，そして一般に使用するDesktop環境まで幅広く利用できる．あらゆるDeviceがNetworkを形成していく中で，A9N MicrokernelによるEcosystemはその基盤となることが期待される．

#v(0.5em)

== 6．普及の見通し
現在途中まで完成しているA9N MicrokernelのDocumentに引き続き，NunやKOITO，`liba9n`のDocumentを作成する．これにより新規Userを獲得し普及させていく予定である．また，複数人程度のContributorを獲得し，継続して開発を実施する．

#v(0.5em)

== 7．クリエータ名

伊組 烈火（フリーランス）

#v(0.5em)

== 8．関連URL

#let link_with_description(url: "example.com", description: [This is an Example]) = {
    block(width: 100%)[
        #set align(left)
        *#link(url)*
        #linebreak()
        #pad(left: 2em)[
            #description
        ]
    ]
}

#link_with_description(url: "https://github.com/horizon2038/A9N", description: "A9N Microkernel")
#link_with_description(url: "https://github.com/horizon2038/A9NLoader", description: "A9N Boot Protocol(x86_64) に従ったReference Bootloader実装")
#link_with_description(url: "https://github.com/horizon2038/Nun", description: "A9N Microkernel上で動作するOSを開発するためのRust製Framework")

#show bibliography : set heading(level: 2)
// #show bibliography : set text(4pt)

#bibliography("/resources/references.bib", title: "参考文献")
