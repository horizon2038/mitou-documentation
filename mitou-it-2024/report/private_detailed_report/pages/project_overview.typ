= プロジェクト概要

== A9N Microkernel

A9N Microkernelは既存Systemの課題を解決するために設計されたMicrokernelである．
Object-Capability ModelによるCapability-Based Securityを採用し，SecureなUser-Level Memory Managementを可能とする．
また，高速なIPC機構によるLow-Latencyな通信を実現する．

== Nun Operating System Framework

NunはA9N Microkernel上にOSを構築するためのRust製Frameworkである．
KernelはInit ProtocolをもってInitial Serverを起動するが，このFrameworkはそのProtocolに沿うOSを構築するために最小限の抽象化を提供する．
Rustを用いることでType SafetyやMemory Safetyを保証し，またCargoによる優れたBuild Systemを享受できる．

== KOITO

KOITOはNunによって実装される，A9N Microkernel上で動作するOSである．
A9Nによって提供されるMechanismを用い，それに対応するPolicyを実装するLayerといえる．
実態としては複数のServerで実現される抽象概念であり，Initial Server, POSIX Compatible Server, User-Level Memory Management Serverによって構成される．

== `liba9n`

`liba9n`はA9N Microkernelのために設計されたC++20 Template Libraryである．Standard Libraryに一切依存しないため，EmbeddedなFreestanding環境でModernなError Handling機構を使用できる．
- `liba9n::std`は`libc++`のSubsetであり，基本機構やMeta ProgrammingのためのUtilityを提供する．
- `liba9n::option<T>`はHaskellの`Maybe`に相当する型を提供する．Monadic OperationをSupportし，逐次処理の高度な抽象化を用いた開発を可能とする．
- `liba9n::result<T, E>`はHaskellの`Either`に相当する型を提供する．`liba9n::option<T>`と同様にMonadic OperationをSupportする．
- `liba9n::not_null<T>`は`liba9n::option<T>`や`liba9n::result<T, E>`で参照を扱うために設計された型である．型レベルでPointerがNullでないことを保証する．

== A9NLoader

A9NLoaderはA9N Boot Protocol(x86_64)に準拠したBoot LoaderのEDK2によるReference Implementationである．UEFI搭載のComputer上でA9N MicrokernelとInit Protocolに準拠したInit ServerをMemory上にLoadする．
その後，KernelへControlを委譲してSystem全体のEntry Pointとする．
