#+feature dynamic-literals
package shared

import b2 "vendor:box2d"
import math "core:math"

Wire_Body :: struct { pose: Pose, rotation: b2.Rot }

read_body_state :: proc(body: b2.BodyId) -> Wire_Body {
 rotation:=b2.Body_GetRotation(body)
 return {pose={position=from_b2(b2.Body_GetPosition(body)),angle=math.atan2(rotation.s,rotation.c),velocity=from_b2(b2.Body_GetLinearVelocity(body)),angular_velocity=b2.Body_GetAngularVelocity(body)},rotation=rotation}
}
