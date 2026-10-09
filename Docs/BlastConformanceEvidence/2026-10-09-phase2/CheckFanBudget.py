"""Independent analytic feasibility check, without importing Unity or the evaluator."""
import json, math
radius, resistance, front = 5.0, 4.0, 1.0
limit_angle = math.acos(front / radius)
# Inside the cover: cost = s + 4 * (s - 1/cos(theta)).
near_reach = (radius + resistance * front) / (1 + resistance)
far_reach = (radius + resistance * front / math.cos(limit_angle)) / (1 + resistance)
variation = 2 * (far_reach - near_reach)
print(json.dumps({
    "radius": radius, "stop_x_at_zero": near_reach,
    "limit_angle_degrees": math.degrees(limit_angle),
    "limit_reach": far_reach, "two_sided_total_variation": variation,
    "reviewed_sector_variation_bound": 0.0005,
    "minimum_sectors_in_cover_angles_only": math.ceil(round(variation, 12) / 0.0005),
    "reviewed_sector_budget": 4096,
    "central_cost_to_core": 1 + (1 + 4) * 1,
    "central_cost_through_core": 1 + (1 + 4) * 1 + (1 + 1) * 2,
    "central_penetration_radius_5": (5 - 1) / (1 + 4),
    "central_core_penetration_radius_8": (8 - 6) / (1 + 1),
}, indent=2))
