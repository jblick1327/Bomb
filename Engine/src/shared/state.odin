#+feature dynamic-literals
package shared

import math "core:math"

finite :: proc(value: f32) -> bool { return !math.is_nan(value) && !math.is_inf(value) }

valid_vec :: proc(v: Vec2) -> bool { return finite(v.x) && finite(v.y) }
