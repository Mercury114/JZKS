set evidence_dir [file dirname [file normalize [info script]]]
open_wave_database [file join $evidence_dir cache_axi_bridge_tb.wdb]
open_wave_config [file join $evidence_dir cache_axi_bridge_tb.wcfg]
