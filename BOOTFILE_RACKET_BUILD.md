# Build boot files

ChezScheme from Cisco provides the initial boot files required to compile Chez. The Racket version does not.

In order to build these you need to have a Racket pre-installed and perform the following steps:

* Install the package `cs-bootstrap` (`-D` will skip building documentation).
```
$ raco pkg install -i -D cs-bootstrap
```

* Setup the boot files architecture. For `i386` (32-bits intel) use `MACH=i3le` (without threads) or `MACH=i3le` (with threads). For `x86_64` (64-bits intel) use `MACH=a6le` (without threads) or `MACH=ta6le` (with threads).
```
$ cd ChezScheme
ChezScheme $ MACH=... racket -l cs-bootstrap
```

Should finish by printing:
```
Writing petite.boot
Writing scheme.boot
```

If this doesn't work open a [bug upstream](https://github.com/racket/ChezScheme/issues/new).


