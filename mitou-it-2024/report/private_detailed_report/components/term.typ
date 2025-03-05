#let technical_term(description, name: [Example]) = context {
    block(width: 100%)[
        #set align(left)
        *#name*
        #linebreak()
        #pad(left: 2em)[
            #description
        ]
    ]
    v(1em)
}

