#import "@preview/cetz:0.3.2"

#let draw_monolithic_kernel() = {
    figure(
        cetz.canvas({
            import cetz.draw: *

            group(name: "microkernel", anchor: "north", {
                group(
                    name: "app",
                    content(
                        (0, 0),
                        text(bottom-edge: "descender")[#set align(center); Application],
                        padding: (x: 4.5, y: 0.5),
                        frame: "rect",
                        anchor: "north",
                    )
                )

                group(
                    name: "kernel", anchor: "north", on-xz(y: -1, {
                        content(
                            (0, 0),
                            block()[
                                #text(bottom-edge: "descender")[
                                    File System, Device Driver, Network Stack, \ 
                                    IPC, Scheduling, Interrupts 
                                ]
                            ],
                            padding: (x: 2, y: 0.5),
                            frame: "rect",
                            fill: luma(240),
                            name: "kernel",
                            anchor: "north",
                        )
                    })
                )

                line("app", "kernel", mark: (end: "triangle"))
            })
        }),
        caption: "Monolithic Kernel"
    )
}

#let draw_microkernel() = {
    figure(
        cetz.canvas({
            import cetz.draw: *

            group(name: "microkernel", anchor: "north", {
                group(
                    name: "app",
                    content(
                        (0, 0),
                        text(bottom-edge: "descender")[#set align(center); Application],
                        padding: (x: 4.5, y: 0.5),
                        frame: "rect",
                        anchor: "north",
                    )
                )

                group(
                    name: "os", anchor: "north", on-xz(y: -1, {
                        content(
                            (0, 0),
                            text(bottom-edge: "descender")[File System],
                            padding: (x: 0.5, y: 0.5),
                            name: "file_system",
                            frame: "rect",
                            anchor: "north",
                        )
                        content(
                            (3.5, 0),
                            text(bottom-edge: "descender")[Device Driver],
                            padding: (x: 0.5, y: 0.5),
                            name: "device_driver",
                            frame: "rect",
                            anchor: "north",
                        )
                        content(
                            (-3.5, 0),
                            text(bottom-edge: "descender")[Network Stack],
                            padding: (x: 0.5, y: 0.5),
                            name: "network_stack",
                            frame: "rect",
                            anchor: "north",
                        )
                    })
                )

                group(
                    name: "kernel", anchor: "north", on-xz(y: -2.7, {
                        content(
                            (0, 0),
                            text(bottom-edge: "descender")[IPC, Scheduling, Interrupts],
                            // [IPC, Scheduling, Interrupts],
                            padding: (x: 3.5, y: 0.5),
                            frame: "rect",
                            fill: luma(240),
                            name: "kernel",
                            anchor: "north",
                        )
                    })
                )

                line("app", "os", mark: (end: "triangle"))
                line("os", "kernel", mark: (end: "triangle"))

            })
        }),
        caption: "Microkernel"
    )
}
