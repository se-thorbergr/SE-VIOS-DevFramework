// VIOS PB Script template (C# 6 / MDK²-SE)
// Enclosure rule: all code must be inside IngameScript.Program

// Curated using directives for convenience when editing outside a full IDE.
// They don’t appear in Space Engineers’ in-game editor at all; copy needed usings
// manually when pasting into other PB Scripts or Mixins.

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
    // PB entry point must be `public partial class Program : MyGridProgram`
    public partial class Program : MyGridProgram
    {
        // VIOS bootstrap fields
        IVIOSKernel _kernel;
        IEnv _env;
        IConfig _cfg;

        public Program()
        {
            // Minimal VIOS composition root
            _env = new Env(this);
            _cfg = new IniConfig(this);
            _kernel = new VIOSKernel();
            _kernel.Init(_env, _cfg);

            // Register starter modules (safe to remove/replace)
            _kernel.RegisterModule(new PowerModule());
            _kernel.RegisterModule(new ScreenManagerModule());

            // Default update cadence (configure via CustomData if desired)
            _kernel.Start(UpdateFrequency.Update10 | UpdateFrequency.Update100);
        }

        public void Save()
        {
            // Persist compact state to PB Storage
            _kernel?.Save();
        }

        public void Main(string argument, UpdateType updateSource)
        {
            try
            {
                // Bounded tick (scheduler/router/modules)
                _kernel?.Tick(updateSource, argument);
            }
            catch (Exception ex)
            {
                // Top-level safety net: keep PB responsive
                Echo("VIOS ERROR: " + ex.Message);
            }
        }
    }
}
