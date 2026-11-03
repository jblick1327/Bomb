package main

import "core:fmt"
import "core:os"
import "core:strconv"

main :: proc() {
	if err:=os.make_directory_all("output"); err!=nil {
		fmt.eprintln("Could not create output directory:",err)
		os.exit(1)
	}
	for arg,i in os.args[1:] {
		if arg=="--soak" {
			minutes:=20
			if i+2<len(os.args) { n,ok:=strconv.parse_int(os.args[i+2]); if !ok || n<1 { fmt.eprintln("--soak expects positive whole minutes"); os.exit(1) }; minutes=n }
			run_soak(minutes); return
		}
		if arg=="--soak-fixture" {
			prefix:=string("output/soak-fixture"); if i+2<len(os.args) { prefix=os.args[i+2] }; run_soak_fixtures(prefix); return
		}
		if arg=="--smoke-msaa" { run_sandbox(true,false,true); return }
		if arg=="--smoke" { run_sandbox(true); return }
		if arg=="--smoke-input" { run_sandbox(true,true); return }
		if arg=="--help" { fmt.println("odin run src -out:build/BOM.exe -- [--soak [minutes] | --soak-fixture [output-prefix] | --smoke-msaa | --smoke | --smoke-input | --help]"); return }
	}
	run_sandbox()
}

