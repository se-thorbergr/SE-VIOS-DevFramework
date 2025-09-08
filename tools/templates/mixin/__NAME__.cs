// SCAFFOLD-STRIP-START
// Template: __NAME__.cs  (renamed to "<CLASS>.cs" by the scaffolder)
// Tokens replaced during scaffolding:
//   __NAME__   -> project/repo name
//   __CLASS__  -> primary type name (defaults to project name, or --class value)
//
// Notes:
// - Mixins are filename-agnostic, but every mixin must declare `partial class Program`
//   (do not inherit MyGridProgram).
// - Keep mixin type names neutral (no "VIOS" prefix). Use branded interfaces from VIOS.Core.
//
// This file includes a curated set of using directives for convenience when editing
// outside a full IDE. They don’t appear in Space Engineers’ in-game editor at all;
// copy needed usings manually when pasting into other PB Scripts or Mixins.
// SCAFFOLD-STRIP-END

using Sandbox.Game.EntityComponents;
using Sandbox.ModAPI.Ingame;
using Sandbox.ModAPI.Interfaces;
using SpaceEngineers.Game.ModAPI.Ingame;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using VRage;
using VRage.Collections;
using VRage.Game;
using VRage.Game.Components;
using VRage.Game.GUI.TextPanel;
using VRage.Game.ModAPI.Ingame;
using VRage.Game.ModAPI.Ingame.Utilities;
using VRage.Game.ObjectBuilders.Definitions;
using VRageMath;

namespace IngameScript
{
    // Required by VIOS mixin policy: keep enclosure under IngameScript.Program (no visibility/base).
    partial class Program
    {
        // SCAFFOLD-STRIP-START
        // Rename via scaffolder (--class __CLASS__).
        // SCAFFOLD-STRIP-END
        /// <summary>
        /// Primary mixin type for '__NAME__'. 
        /// Keep names neutral; avoid "VIOS" in non-core types.
        /// </summary>
        class __CLASS__
        {
            // Add fields/methods here. Keep hot paths allocation-free.
        }
    }
}

/* --------------------------------------------------------------------------
 * If this mixin will be a VIOS Module later, replace the class above with
 * the skeleton below after referencing VIOS.Core. Leaving it commented
 * preserves first-compile success in empty repos.
 *
 * using System.Text;
 *
 * namespace IngameScript
 * {
 *     partial class Program
 *     {
 *         class __CLASS__ : IVIOSModule
 *         {
 *             public string Name { get { return "__CLASS__"; } }
 *             public void Init(VIOSContext ctx, IModuleRegistrar reg) { }
 *             public void Start(VIOSContext ctx) { }
 *             public void Tick(VIOSContext ctx) { }
 *             public void Stop(VIOSContext ctx) { }
 *             public void OnMessage(ref VIOSPacket p, VIOSContext ctx) { }
 *             public void DescribeStatus(StringBuilder sb) { }
 *         }
 *     }
 * }
 * --------------------------------------------------------------------------*/
