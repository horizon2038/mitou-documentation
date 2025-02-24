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

A9N Microkernelの実装にはObject-Capability Model @DennisEtAl:1966 によるCapability-Based Securityを採用し，従来のシステムが抱えていた課題を解消した．
Capabilityは特権的リソース : Objectに対するアクセス権限を示すUniqueなTokenである．
従来のACLを用いたアクセス $dash.em.two$ リソース自身がPermissionを確認する方式とは異なり，該当Capabilityの所有者のみが操作を実行可能である．
このように，PoLPを満たしつつも柔軟なアクセス制御を実現する．

Capabilityを用いることで，KernelはHeapを持たず，なおかつSecureにUser-Level Memory Managementを実現することが可能となる．

=== Capabilityの操作体系

CapabilityはTokenであり，間接的にObjectへアクセスするためのHandleである．
要するに，あらゆる特権的操作はObjectが持つ固有機能の呼び出しとしてModel化される．したがって，Object-Oriented ProgrammingにおけるObjectのMethod Callと同等に捉えることができる．

A9N Microkernelにおいて, Objectの操作にはCapability Descriptorと呼ばれる符号なし整数型を用いる．

```rust
foo_operation(foo: capability_descriptor, args ...)
```

=== Generic Capability

Generic Capabilityは物理的なMemoryを抽象化したCapabilityである．
GenericはBase Address, 

=== C++におけるObject-Capability Modelの設計と実装

== Nun Operating System Frameworkの開発

== KOITOの開発

== `liba9n`の開発

== A9NLoaderの開発
