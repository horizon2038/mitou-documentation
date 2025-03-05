= プロジェクト概要


前述したように，既存のMonolithic Kernel-Based Systemは柔軟に欠け，Security上のリスクや保守性の低下といった重大な問題を抱えている．また，Microkernel-Based Systemはこれらの問題を解決しているように見えるが，性能低下やKernel-LevelでのMemory Managementといった別の問題を抱えている．

本プロジェクトではこれらの問題を解決するために，新たなSecurity Modelと高い性能を兼ね備えた次世代MicrokernelであるA9Nを開発した．そして，これをBaseとしてOS構築を支援するためのFrameworkであるNunと，それを用いて実装されるOSであるKOITOを開発した．これにより，UserがDynamicなUsecaseに合わせたSecureなSystemを構築できる環境を提供する．
さらに，A9N Microkernelの開発を継続していくため`liba9n`というModernなError Handling機構を提供するC++20用のLibraryを開発した．このLibraryにより，Kernel DeveloperとKernelのUserという2つの立場における，開発の継続性や安全性の妥当性を保証することが可能となる．

#v(1em)

// == A9N Microkernel

#figure(
    image("/resources/A9N_logo.png", width: 35%),
    caption: [
        A9N Microkernelのロゴ
    ]
) <a9n_logo>


A9N Microkernel（@a9n_logo）はMonolithic KernelとMicrokernelの課題を解決するために設計された, Hardware Abstraction Layer（HAL）による移植容易性を持つMicrokernelである．Object-Capability ModelによるCapability-Based Securityを採用し，抽象Memory CapabilityによるSecureなUser-Level Memory Managementを可能とする．また，高速なIPC機構によるLow-Latencyな通信を実現する．さらに，A9NのKernel-Level APIはArchitecture-Independentであるため，Device DriverとVirtual Machine Monitor（VMM）を除くほぼ全ての機構は容易にPorting可能である．


#v(1em)
// == Nun Operating System Framework

NunはA9N Microkernel上にOSを構築するためのRust製Frameworkである．KernelはInit ProtocolをもってInitial Serverを起動するが，このFrameworkはそのProtocolに沿うOSを構築するために最小限の抽象化を提供する．Rustを用いることでType SafetyやMemory Safetyを保証し，またCargoによる優れたBuild Systemを享受できる．
通常，Microkernel-Based SystemのStartupは複雑な処理Flowを持つが，Nunはこれを簡略化し，UserがOSを開発する際の負担を軽減する．

#v(1em)
// == KOITO

#figure(
    image("/resources/KOITO_logo.png", width: 40%),
    caption: [
        KOITOのロゴ
    ],
    gap: 2em
) <koito_logo>

KOITO（@koito_logo）はNunによって実装される，A9N Microkernel上で動作するOSである．A9Nによって提供されるMechanismを用い，それに対応するPolicyを実装するLayerといえる．実態としては複数のServerで実現される抽象概念であり，Initial Server, POSIX Compatible Server, User-Level Memory Management Serverによって構成される．
KOITOを構成する各ServerはすべてUser-Levelで動作するため，極端なUsecaseから普遍的なUsecaseまで動的かつ柔軟に対応することが可能となる．

KOITOは実用OSとしての役割と，A9N-BasedなOSのReference実装としての役割を兼ね備える．したがって，Userは新規OSの開発に際して，KOITOの各Componentを再利用することができる．

#v(1em)
// == `liba9n`

`liba9n`はA9N Microkernelのために設計されたC++20 Template Libraryである．Standard Libraryに一切依存しないため，EmbeddedなFreestanding環境でModernなError Handling機構を使用できる．
- `liba9n::std`は`libc++`のSubsetであり，基本機構やMeta ProgrammingのためのUtilityを提供する．
- `liba9n::option<T>`はHaskellの`Maybe`に相当する型を提供する．Monadic OperationをSupportし，逐次処理の高度な抽象化を用いた開発を可能とする．
- `liba9n::result<T, E>`はHaskellの`Either`に相当する型を提供する．`liba9n::option<T>`と同様にMonadic OperationをSupportする．
- `liba9n::not_null<T>`は`liba9n::option<T>`や`liba9n::result<T, E>`で参照を扱うために設計された型である．型レベルでPointerがNullでないことを保証する．

#v(1em)
// == A9NLoader

A9NLoaderはA9N Boot Protocol(x86_64)に準拠したBoot LoaderのEDK2によるReference Implementationである．UEFI搭載のComputer上でA9N MicrokernelとInit Protocolに準拠したInit ServerをMemory上にLoadする．その後，KernelへControlを委譲してSystem全体のEntry Pointとする．
