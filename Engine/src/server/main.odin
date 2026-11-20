package main
import "core:os"
import shared "../shared"
main :: proc() { if !shared.net_real_cli_server(os.args[1:]) { os.exit(1) } }
