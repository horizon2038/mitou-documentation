= 開発成果の特徴

== HAL

A9N MicrokernelはHardware-Dependentな部分を分離するためにHALを導入し，高いPortabilityを達成する．
そのため，A9N MicrokernelにおけるKernel部は完全にHardware-Independentである．KernelはHALのInterfaceに対して操作を行い，HALの各Architectureにおける実装はそのInterfaceを実装する．
また，このようなHardware-Dependent部分の分割はSource Code Levelのみならず，Build System Levelでも達成されている (cf., @a9n::build_system)

== Capability

A9N MicrokernelとKOITOはCapabilityを用いてSecureにUser-Level Memory Managementを実行する．それを用いることにより，KOITOは完全にUser-LevelのSLAB AllocatorとBuddy Allocatorを実現した．
また，A9N Microkernelの持つCapability APIはHardware-Independentである．したがって，簡単にMemory Management Serverを他のArchitectureにPortingできる．

#pagebreak()

== 高速なIPC

A9N Microkernelは細かな最適化とModernなSoftware Architectureにより，極めて高速なIPCを実現した．
以下にA9N Microkernelと既存 MicrokernelのIPC Round-Trip Latencyを示す (cf., @ipc_benchmark)．

#figure(
    table(
      columns: (1fr, 1.5fr, 1fr),
      inset: 10pt,
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
    caption: [Single-Core IPC Round-Trip Latency; cf., @ZeyuMiEtAl:2019, @seL4Performance:2022],
) <ipc_benchmark>

Intel® N150\@3.6GHz Processorにおいて，A9N MicrokernelはIPC Round-Trip Latencyとして590Cycles (91.4ns) を達成した．
この結果はx86_64 Architectureにおいてほぼ世界最速といえる値である．

== NunによるOS開発の簡易化

Nun Operating System Frameworkにより，A9N MicrokernelをコアとするOSの開発が極端に簡易化できる．
これを証明するためにDemoDayではNunを用いて最小のOSを開発するLive Codingを実施し，およそ2分でBuildから実行までを達成した．

== 先行研究

3rd-Generation Microkernelの先行事例と比較し，A9N Microkernelの特徴を示す．

=== Zircon @Zircon:2025 

ZirconはGoogleによって開発されたLittle KernelをベースとするMicrokernelである．

==== Memory Management

ZirconはHandle#footnote[Capabilityと同等の，Kernel Objectを操作するために使用されるTokenのこと．]を用いたUser-Level Memory Managementを実現しているが，KernelによってPage TableのManagement Policyを持つ @ZirconVMO:2025．

==== Virtualization

ZirconはHardware-Assisted VirtualizationをSupportし，Fuchsiaと合わせてType-2 Hypervisorとしての機能を提供する @FuchsiaVirtualization:2025．

==== Userland Software

Userland SoftwareとしてFuchsiaという成熟したOSを持つ．

=== seL4 @seL4:2025

seL4はNICTAのTrustworthy Systemsによって開発されたCapability-Based Microkernelである．
高速なIPC機構を備え，かつFormal VerificationによりKernelのCorrectnessを証明している．

==== Memory Management

Kernel Heapを持たず，ほぼすべてのMemory ManagementをCapabilityによってUser-Levelで行う．
また，これらは最適化の観点からあえてHardware-DependentなKernel-Level APIを持つと明言されている @seL4DesignPrinciples:2020．

==== Virtualization

seL4はHardware-Assisted VirtualizationをSupportし，VirtualizationType-1 Hypervisorとしての機構を提供する．
これらはCapabilityを用いて操作可能であり，大部分の機能はUser-Level VMMで実現される．
ただし，Virtualization APIの殆どがHardware-Dependentであるため抽象度は低い．例えばx86_64の場合，Virtualization APIはVMCSを操作するための薄いWrapperに過ぎない．

==== Userland Software

seL4のUserland Softwareは特に成熟していないが，Nunと同様にCAmkES @CAmkES:2025 というComponent-Based Frameworkが提供される．
また，準標準となるようなOSとしてLionsOSが開発されている．

=== A9Nの優位点

==== Memory Management

A9N MicrokernelはKernel Heapを持たず，seL4と同様にCapabilityを用いたUser-Level Memory Managentを実現する．
また，基本的にKernel-LevelAPIはHardware-Independentであるため，他のArchitectureへ容易にPortingできる．

==== Virtualization

A9N MicrokernelはType-1 Hypervisor機構を備え，Capability-Based Virtualizationを実現する．
また，Virtual Message RegisterのLayout以外はHardware-IndependentなAPIであり，Portingや概念の理解が容易である．
