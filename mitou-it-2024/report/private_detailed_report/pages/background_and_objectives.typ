#import "@preview/cetz:0.3.2"

#import "/components/kernel.typ" : draw_monolithic_kernel, draw_microkernel

= 背景及び目的

== 計算機の民主化

近年，計算機の民主化によるIoTの拡大は大きなムーブメントを生み出している．
Moore's Law @Moore:1965 で予見されたように，面積当たりのトランジスタ数は指数関数的に増加した．
その結果として，軍需産業や学術研究機関に限られていた計算機の利用は大衆化し，黎明期とは比較にならないほどの賢さを数多の人間が手にすることとなった．

民主化に伴い，そのHardwareを司るKernelやOSといった基盤ソフトウェアの存在感も大きく増している．
KernelはSystemとHardwareを接続するInterfaceであり，資源管理の抽象化を担うものである．OSはKernelの提供するAPIを用い，要件達成のための機構をUserに提供する．このように，複雑さはこれらの抽象化を行うLayerによって隠蔽される．

== Monolithic Kernelとその限界

しかしながら，既存のKernelやOSはコードベースの肥大化による問題を抱えている．
現在広く使われているLinux Kernelを例とする．
2024年時点で2000万行を超えるコードを有する @Larabel:2020 巨大なプロジェクトであり，現在進行系でコードベースは成長を遂げている．
現在はOSSコミュニティの”人海戦術”とも言える体制によって保守されているが，このアプローチには問題がある．

まず，人的リソースの限界が挙げられる．
計算機技術の進歩により，KernelやOSの機能は日々拡張されている．現在以上のペースでコードベースが拡大した場合に伴う開発の困難化は明白である．

次に，利害関係者の増加に伴う意思決定スピードの低下も問題である．
巨大なプロジェクトは成長とともに関係者も例外なく増加する傾向にあるが，これには開発の停滞化によるスケールアップの困難さが生じる.
つい先日も，Rust対応のためにLinux KernelへDMA APIを呼び出す抽象化Layerを追加する提案がMaintainerによって強く否定される自体が発生した @Claburn:2025 ．


また，肥大化によるTCBの拡大はSecurity上のリスクを増大させる．
KernelはHardwareなどの抽象度が異なるLayerを直接操作するものであり，最も高い権限を持つ．
言い換えれば，Kernelは上に存在するすべてのSoftwareから信頼される対象である．
特権的なコンポーネントの拡大に伴って攻撃対象は拡大するため，System全体の信頼性やSecurity耐性は低下する．
コードの殆どはDevice Driverであり，Kernel-Levelで多くの外部機構を扱う．したがって，Device DriverがCrashした場合System全体がダウンしてしまう．
実際，商用OSであるWindows XPがCrashする要因の85%はDevice Driverに起因していた @SwiftEtAl:2006 ．また, Linux KernelにおけるDevice Driverのバグ率は他のKernel部分と比較して7倍高いという結果 @ChouEtAl:2001 もある.

このように，一枚岩のMonolithicなKernel (@monolithic_kernel) やOSはもはや現代の要求に適合しない．
したがって，これを置き換える新たなアーキテクチャが求められている．

#v(1em)
#draw_monolithic_kernel() <monolithic_kernel>
#v(1em)

== Microkernelとその限界

前述の問題を解決するためのアプローチとして有力なのがMicrokernel (@microkernel) である．
このKernelは従来のMonolithicなKernelとは異なり，提供する機構を最小化することでUserへ最小限のPrimitiveのみを提供するような設計手法である．
このArchitectureでは，ほぼ全てのDevice DriverやFile System，Network Stackといった機能はKernel SpaceからUser Spaceへ移動される．したがって，不安定なDevice DriverがCrashしてもKernelがダウンすることはない．
また，Systemの構成を要件に合わせてDynamicに変更することも容易となる．この仕組みはPolicy/Mechanism Separation @LevinEtAl:1975 を満たすものである．

#v(1em)
#draw_microkernel() <microkernel>
#v(1em)

このアプローチは一見完璧なように見えるが，実際にはいくつかの問題が存在する．

一般的に，Microkernelは従来のMonolithic Kernelと比較して性能が劣るとされている．
Monolithic Kernelでは特権的機能の呼び出しが1回のSystem Callで完結するため非常に高速である．Kernel内部ではFunction Callの連鎖に過ぎないためである．
しかし，Microkernelでは多くの場合IPCによって処理が複数のServerへ委譲される．IPCはUser SpaceからKernel Spaceへ，またその逆のSwitchを実行する．したがって，Context Switchの回数が増加し性能が低下する．
*Single Server*と呼ばれる，Device DriverやFile Systemといった機構を単一のServerとして実装してしまうことでIPCの実行回数を削減するアプローチも存在するが，不安定さの分離やDynamicな構成変更といったMicrokernelの利点を損なうことになる．

また，Microkernelはすべての機構をUser-Levelで実行できるわけではなく，Process SchedulingやMemory Managementといった機構の分離は困難である．

まず，Clock Interrupt毎にUser-Level Schedulerを呼び出すアプローチには速度面の問題がある．
一般的にClock Interruptは100-1000Hzの高頻度で発生するが，IPCの実行は先述した通り高コストである．Overheadを削減するためLinuxのようにKernel内部へVMを実装する手法(e.g., eBPF, Wasm)も考えられるが，これではMicrokernelの利点を損なうだけである．

次に，Memory Managementではどうだろうか？ 残念ながら，これにはSecurityの問題がある．
Device Driverと同様にMemory ManagementをUserへ移譲することを考える．MemoryのMapやUnmap，Page Tableの管理をKernel-LevelではなくUser-Levelで実行したい．
しかしながら，これではKernelに必要な領域をKernel自身が確保できなくなってしまう．この問題に対処すべくKernelにStaticなHeapを持たせる手法が考えられるが，使い切ってしまった場合に動作が不可能となる．
User-LevelのServerにIPCを送信して委譲する手法も考えられるが，これでは委譲先のServerにKernelのMeta Dataが漏洩してしまうため，PoLP @SaltzerEtAl:1973 を満たすことができない．
これらの問題から，多くのMicrokernelはMemory ManagementをKernel-Levelで実装している．

如何にすれば，PoLPを保ったまま柔軟性や安定性を手に入れることができるだろうか？
これには新しい手法が必要である！
