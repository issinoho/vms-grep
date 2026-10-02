$! VMS_PROBE.COM - read-only environment discovery for the vms-grep port
$ set noon
$ say = "write sys$output"
$ say "=== SYSTEM"
$ say f$getsyi("nodename"), " ", f$getsyi("arch_name"), " ", f$getsyi("version"), " ", f$getsyi("hw_name")
$ say "=== CC"
$ cc/version
$ say "=== MMS / MMK"
$ mms/ident
$ show symbol mmk
$ say "=== PRODUCTS"
$ product show product/full
$ say "=== CRTL / GNV logicals"
$ show logical gnv$*
$ show logical decc$*
$ show logical dcl$path
$ say "=== CRTL headers"
$ directory/size/date sys$library:decc$rtldef.tlb
$ say "=== PROCESS"
$ show process/parse
$ say "=== DONE"
