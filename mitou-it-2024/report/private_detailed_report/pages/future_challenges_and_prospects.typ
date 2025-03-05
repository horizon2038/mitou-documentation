= 今後の課題，展望

== Document

A9N MicrokernelのDocumentについてはある程度整備されているが，まだ不十分である．また，その他のProject(i.e., Nun, KOITO, A9NLoader, `liba9n`)については全くDocumentが存在しない．Documentの不足はUserの拡充における重大な障害となるため，優先してDocumentの整備を行っていく予定である．

== Porting

HALが存在しKernelの分離は成されている一方で，まだ他ArchitectureへのPortingが行われていない．Test Codeを実行するためのHAL実装は存在しているが，これはPortingとは言い難い．まずはRISC-V 64bit(RV64)へのPortingを行い，その後AArch64へのPortingを実施する予定である．

== POSIX Compatibility

現在のPOSIX Serverは不完全であり，POSIX準拠のSoftwareを完全に移植できていない．現在の実装の根幹となるNewlibのPOSIX対応箇所は限定的であるため，POSIX-Compatibleな移植しやすい実装であるmlibcへ移行する予定である．

== User-Level Virtual Machine Monitor

Virtualization Extensionである各Capability（i.e., Virtual CPU, Virtual Address Space, Virtual Page Table）についての実装はある程度進んでいる一方で未だ未完成である．というのも，何度も手戻りが発生し3回以上のAPI再設計を実施したためである．また，この不安定なVirtualization APIのUserであるVMMの実装も当然ながら未完成である．ただし，現在API設計は現在ほぼ完了し成熟へ向かっている．また，Virtualization機構を実際に使用するHAL内の実装もほぼ完了している．したがって，数週間以内には簡易的なVMMの実装を完了し，Linuxを動作させることを目指す．

== Future

A9N MicrokernelやNun, KOITOの開発は未踏期間終了後も継続していき，既存Systemの置換を中期的な目的とする．時間は必要だが，既存資産の再利用をPOSIX ServerやVirtualization Extensionによって実現することにより，段階的な移行をSupportしていきたいと考えている．

現代の巨大なSystemを1人の力で実装することは難しい．だが，Microkernelのように小さいKernelは1人でも大半を実装できる．もちろんOSSでありCommunityを形成して開発していくことも考えている．ただ，人海戦術に依存せずともに少人数も開発の継続が可能であり，またその意思も持っている．．

普及後はMicrokernel-BasedなSystemを用いて計算機同士のCommunicationを無限にScale-Outし，Ubiqutous Computingを実現していきたいと考える．．
