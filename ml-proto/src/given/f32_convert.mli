(* WebAssembly-compatible type conversions to f32 implementation *)

val demote_f64 : F64.t -> F32.t
val convert_s_i32 : int32 -> F32.t
val convert_u_i32 : int32 -> F32.t
val convert_s_i64 : int64 -> F32.t
val convert_u_i64 : int64 -> F32.t
val reinterpret_i32 : int32 -> F32.t
