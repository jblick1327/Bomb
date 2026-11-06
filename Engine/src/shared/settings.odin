#+feature dynamic-literals
package shared



Blast_Mode :: enum { Manual, Falling_Bombs }

Sandbox_Settings :: struct {
	blast_radius: f32,
	blast_mode: Blast_Mode,
	seed: u8,
}

DEFAULT_SANDBOX_SETTINGS :: Sandbox_Settings{blast_radius=5.0,seed=42}
