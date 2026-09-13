# Read-only command discovery; no project opened or build requested.
foreach pattern {*report* *timing* *read* *open* *export* *load* *write*} {
    puts "$pattern: [lsort [info commands $pattern]]"
}
