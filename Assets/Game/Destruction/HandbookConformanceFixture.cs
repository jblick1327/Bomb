using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public sealed class ConformanceIds
    {
        public MaterialEntityId Support, Platform, Character, Bomb, Connector, Hold, Participant;
    }
    public static class HandbookConformanceFixture
    {
        public static CanonicalPolygon2D Rectangle(float x0, float y0, float x1, float y1) => new CanonicalPolygon2D(new[]
            { new Vector2(x0,y0), new Vector2(x1,y0), new Vector2(x1,y1), new Vector2(x0,y1) });
        public static CanonicalMaterialShape Shape(params CanonicalPolygon2D[] cells) => new CanonicalMaterialShape(cells);
        public static CanonicalPolygon2D Circle(Vector2 center, float radius, int count) => new CanonicalPolygon2D(Enumerable.Range(0, count)
            .Select(i => center + CanonicalGeometry.Rotate(Vector2.right * radius, i * 2 * Mathf.PI / count)));
        public static DefinitionSet Definitions(bool bombEligible = true)
        {
            var specs = new List<DefinitionSpec>();
            foreach (var item in new[] { ("terrain", 2f), ("clay", 1f), ("bomb", 3f), ("light", 0.2f) })
                specs.Add(new DefinitionSpec { kind = DefinitionKind.Material, id = item.Item1, density = item.Item2, friction = 0.4f,
                    hasBlastResistance = true, blastResistance = 0 });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Response, id = "convex-subtraction", destructible = true, minimumRetainedCellArea = 0.01f });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Response, id = "indestructible" });
            foreach (var item in new[] { ("terrain", new Color(0.24f,0.33f,0.39f)), ("clay", new Color(1,0.66f,0.16f)),
                ("bomb", new Color(0.075f,0.085f,0.1f)), ("foundation", new Color(0.43f,0.57f,0.65f)) })
                specs.Add(new DefinitionSpec { kind = DefinitionKind.Appearance, id = item.Item1, tint = item.Item2, depth = 0.2f });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Environment, id = "platform", bodyMode = CanonicalBodyMode.Dynamic, holdEligible = true });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Environment, id = "corpse", bodyMode = CanonicalBodyMode.Dynamic, holdEligible = false });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Level, id = "fixture-foundation", bodyMode = CanonicalBodyMode.Static, holdEligible = true,
                levelCells = new[] { Rectangle(-5,-1,5,0), Rectangle(-4,0,-3,4.5f) }.Select(p => new DefinitionCell { points = p.Vertices.ToArray() }).ToArray() });
            var baseSet = new DefinitionSet(specs);
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Character, id = "fixture-claymate", bodyMode = CanonicalBodyMode.Dynamic, holdEligible = true,
                leftHand = new Vector2(-0.2f,0.3f), rightHand = new Vector2(0.2f,0.3f), leftFoot = new Vector2(-0.15f,-0.35f), rightFoot = new Vector2(0.15f,-0.35f),
                handReach = 1.5f, footReach = 1, corpseRole = baseSet.Reference(DefinitionKind.Environment,"corpse"),
                corpseMaterial = baseSet.Reference(DefinitionKind.Material,"clay"), corpseResponse = baseSet.Reference(DefinitionKind.Response,"convex-subtraction"),
                corpseAppearance = baseSet.Reference(DefinitionKind.Appearance,"clay") });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Bomb, id = "fixture-bomb", bodyMode = CanonicalBodyMode.Dynamic, holdEligible = bombEligible,
                countdownSeconds = 8, blastPower = 1, blastRadius = 0.75f });
            return new DefinitionSet(specs);
        }
        public static BodyDefinitionSelection Selection(DefinitionSet defs, string material, string response, string appearance, DefinitionKind roleKind, string role)
            => new BodyDefinitionSelection(defs.Reference(DefinitionKind.Material, material), defs.Reference(DefinitionKind.Response,response),
                defs.Reference(DefinitionKind.Appearance,appearance), defs.Reference(roleKind,role));
        public static CanonicalMaterialWorld Create(out ConformanceIds ids, bool bombEligible = true)
        {
            var defs = Definitions(bombEligible);
            var world = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator("match-"), defs);
            if (!world.TryReserveEntityIds(7, out var reservation, out var error)) throw new InvalidOperationException(error);
            ids = new ConformanceIds { Support = reservation.Ids[0], Platform = reservation.Ids[1], Character = reservation.Ids[2], Bomb = reservation.Ids[3],
                Connector = reservation.Ids[4], Hold = reservation.Ids[5], Participant = reservation.Ids[6] };
            var supportSelection = Selection(defs,"terrain","indestructible","foundation",DefinitionKind.Level,"fixture-foundation");
            var foundation = defs.Resolve(supportSelection.Role);
            CanonicalMaterialState Body(MaterialEntityId id, CanonicalMaterialShape shape, Vector2 position, BodyDefinitionSelection selection) =>
                new CanonicalMaterialState(id,shape,1,position,0,Vector2.zero,0,defs.Resolve(selection.Role).bodyMode,selection,
                    selection.IsBomb ? new BombCountdown(false,0) : null);
            var bodies = new[] {
                Body(ids.Support, new CanonicalMaterialShape(foundation.levelCells.Select(c => new CanonicalPolygon2D(c.points))), Vector2.zero, supportSelection),
                Body(ids.Platform, Shape(Rectangle(-3,-0.5f,3,0.5f)), new Vector2(0,3), Selection(defs,"terrain","convex-subtraction","terrain",DefinitionKind.Environment,"platform")),
                Body(ids.Character, Shape(Rectangle(-0.3f,-0.4f,0.3f,0.4f)), new Vector2(2,1), Selection(defs,"clay","indestructible","clay",DefinitionKind.Character,"fixture-claymate")),
                Body(ids.Bomb, Shape(Circle(Vector2.zero,0.25f,16)), new Vector2(-1.5f,6), Selection(defs,"bomb","indestructible","bomb",DefinitionKind.Bomb,"fixture-bomb")) };
            var connector = new CanonicalConnector(ids.Connector, ids.Support, ids.Platform, new Vector2(-3,2.7f),new Vector2(-3,3.3f),
                new Vector2(-3,-0.3f),new Vector2(-3,0.3f),5000,0.5f,0.6f);
            var hold = new CanonicalHold(ids.Hold,ids.Character,LimbSlot.RightHand,ids.Platform,new Vector2(2,-0.5f));
            var view = new CanonicalWorldView(bodies,new[] { connector },new[] { hold },new[] { new CanonicalParticipant(ids.Participant,ids.Character) });
            if (!world.TryCommit(new StructuralMutationPlan(world.Generation,view,reservation),out _,out error)) throw new InvalidOperationException(error);
            return world;
        }
    }
}
