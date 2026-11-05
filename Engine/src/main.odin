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
  if arg=="--check-glue-followup" { run_seam_followup_checks();return }
  if arg=="--probe-demo-blasts" { probe_demo_blasts();return }
  if arg=="--diagnose-demo" { run_seam_diagnostics();return }
  if arg=="--check-shapes" { run_shape_checks();return }
  if arg=="--replication-soak" {
   minutes:=20
   if i+2<len(os.args) { n,ok:=strconv.parse_int(os.args[i+2]); if !ok || n<2 { fmt.eprintln("--replication-soak expects whole minutes, at least 2"); os.exit(1) }; minutes=n }
   run_replication_soak(minutes); return
  }
  if arg=="--pose-resolution" {
   minutes:=20
   if i+2<len(os.args) { n,ok:=strconv.parse_int(os.args[i+2]); if ok && n>=1 { minutes=n } }
   run_pose_resolution(minutes); return
  }
  if arg=="--net-soak" {
   minutes:=10
   if i+2<len(os.args) { n,ok:=strconv.parse_int(os.args[i+2]); if ok && n>=1 { minutes=n } }
   run_net_soak(minutes); return
  }
  if arg=="--capture-frames" { directory:=string("output/frames"); if i+2<len(os.args) { directory=os.args[i+2] }; run_frame_captures(directory); return }
  if arg=="--capture-textures" { run_texture_captures(); return }
  if arg=="--check-textures" { run_texture_checks(); return }
  if arg=="--capture-ui" { directory:=string("evidence/textures-ui/after"); if i+2<len(os.args) { directory=os.args[i+2] }; run_ui_captures(directory); return }
  if arg=="--smoke-materials" { run_material_smoke(); return }
  if arg=="--capture-cover" { run_cover_capture(); return }
  if arg=="--capture-mortar" {
   directory:=string("output/mortar"); if i+2<len(os.args) { directory=os.args[i+2] }; run_mortar_captures(directory); return
  }
  if arg=="--measure-mortar" { run_mortar_bridge_measurements(); return }
  if arg=="--mortar-seeds" { run_mortar_seed_study(); return }
  if arg=="--calibrate-mortar" { run_mortar_calibration(); return }
  when BOM_FRAME_BENCH { if arg=="--bench-frames" { run_frame_bench(); return } }
  if arg=="--glass-study" || arg=="--capture-glass" {
   directory:=string("output/glass-shock"); if i+2<len(os.args) { directory=os.args[i+2] }
   if arg=="--glass-study" { run_glass_study(directory) } else { run_glass_captures(directory) }; return
  }
  if arg=="--wood-study" || arg=="--capture-wood" {
   directory:=string("output/wood-splinters"); if i+2<len(os.args) { directory=os.args[i+2] }
   if arg=="--wood-study" { run_wood_study(directory) } else { run_wood_captures(directory) }; return
  }
  if arg=="--capture-rubber-band" {
   directory:=string("output/rubber-band"); if i+2<len(os.args) { directory=os.args[i+2] }
   run_rubber_band_capture(directory); return
  }
		if arg=="--bench-presentation" { run_presentation_bench(); return }
		if arg=="--smoke-editor" { run_sandbox(true,false,false,false,true); return }
  if arg=="--measure-world" { run_world_measurements(); return }
		if arg=="--soak" {
			minutes:=20
			if i+2<len(os.args) { n,ok:=strconv.parse_int(os.args[i+2]); if !ok || n<1 { fmt.eprintln("--soak expects positive whole minutes"); os.exit(1) }; minutes=n }
			run_soak(minutes); return
		}
		if arg=="--soak-fixture" {
			prefix:=string("output/soak-fixture"); if i+2<len(os.args) { prefix=os.args[i+2] }; run_soak_fixtures(prefix); return
		}
		if arg=="--smoke-msaa" { run_sandbox(true,false,true); return }
  if arg=="--smoke-aim" { run_sandbox(true,false,false,true); return }
		if arg=="--smoke" { run_sandbox(true); return }
		if arg=="--smoke-input" { run_sandbox(true,true); return }
		if arg=="--help" { fmt.println("odin run src -out:build/BOM.exe -- [--smoke-materials | --mortar-seeds | --calibrate-mortar | --measure-mortar (BOM_MORTAR_MEASURE=true) | --capture-mortar [directory] | --soak [minutes] | --soak-fixture [output-prefix] | --replication-soak [minutes] | --pose-resolution [minutes] | --net-soak [minutes] | --capture-frames [directory] | --bench-presentation | --measure-world | --glass-study [directory] | --capture-glass [directory] | --wood-study [directory] | --capture-wood [directory] | --capture-rubber-band [directory] | --smoke-msaa | --smoke-aim | --smoke-editor | --smoke | --smoke-input | --help]"); return }
	}
	if err:=os.make_directory_all("layouts"); err!=nil { fmt.eprintln("Could not create layouts directory:",err); os.exit(1) }
	run_sandbox()
}

