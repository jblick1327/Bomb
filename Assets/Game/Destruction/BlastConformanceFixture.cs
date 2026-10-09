using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    // Explicit experiment inputs. These values do not establish material tuning defaults.
    public static class BlastConformanceFixture
    {
        public static MaterialEntityId Id(int sequence) => new MaterialEntityId("blast-" + sequence.ToString("x16"));
        public static DefinitionSet Definitions(float radius, float power = 1)
        {
            var specs = HandbookConformanceFixture.Definitions().Export().ToList();
            foreach (var material in new[] { ("cover", 2f, 4f), ("core", 3f, 1f), ("narrow", 2f, 16f) })
                specs.Add(new DefinitionSpec { kind = DefinitionKind.Material, id = material.Item1, density = material.Item2,
                    friction = 0.4f, hasBlastResistance = true, blastResistance = material.Item3 });
            specs.Add(new DefinitionSpec { kind = DefinitionKind.Response, id = "bounded-subtraction",
                destructible = true, minimumRetainedCellArea = 0.00001f });
            specs.Single(s => s.kind == DefinitionKind.Bomb).blastRadius = radius;
            specs.Single(s => s.kind == DefinitionKind.Bomb).blastPower = power;
            return new DefinitionSet(specs);
        }
        public static CanonicalMaterialState Body(DefinitionSet definitions, MaterialEntityId id,
            CanonicalMaterialShape shape, string material, Vector2 position = default, float rotation = 0,
            DefinitionKind kind = DefinitionKind.Environment, string response = "bounded-subtraction")
        {
            string role = kind == DefinitionKind.Bomb ? "fixture-bomb" : kind == DefinitionKind.Character ? "fixture-claymate" : "platform";
            var selection = HandbookConformanceFixture.Selection(definitions, material, response,
                "terrain", kind, role);
            return new CanonicalMaterialState(id, shape, 1, position, rotation, Vector2.zero, 0,
                definitions.Resolve(selection.Role).bodyMode, selection,
                kind == DefinitionKind.Bomb ? new BombCountdown(false, 0) : null);
        }
        public static CanonicalMaterialWorld World(DefinitionSet definitions, IEnumerable<CanonicalMaterialState> bodies,
            IEnumerable<CanonicalConnector> connectors = null, IEnumerable<CanonicalHold> holds = null,
            IEnumerable<CanonicalParticipant> participants = null)
        {
            var world = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator("blast-"), definitions);
            var view = new CanonicalWorldView(bodies, connectors, holds, participants);
            if (!world.TryReserveEntityIds(view.AllIds.Count(), out var reservation, out var error)) throw new InvalidOperationException(error);
            if (!world.TryCommit(new StructuralMutationPlan(world.Generation, view, reservation), out _, out error))
                throw new InvalidOperationException(error);
            return world;
        }
        public static CanonicalMaterialWorld Layers(float radius, out MaterialEntityId bomb,
            out MaterialEntityId cover, out MaterialEntityId core, float rotation = 0, Vector2 translation = default)
        {
            var definitions = Definitions(radius); bomb = Id(1); cover = Id(2); core = Id(3);
            return World(definitions, new[] {
                Body(definitions,bomb,HandbookConformanceFixture.Shape(HandbookConformanceFixture.Circle(Vector2.zero,0.25f,16)),
                    "bomb",translation,rotation,DefinitionKind.Bomb,"indestructible"),
                Body(definitions,cover,HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(1,-6,2,6)),"cover",translation,rotation),
                Body(definitions,core,HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(2,-6,4,6)),"core",translation,rotation)
            });
        }
    }
}
