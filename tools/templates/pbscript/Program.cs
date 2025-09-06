using Sandbox.ModAPI.Ingame;
using VRage.Game;
using VRage.Game.GUI.TextPanel;

namespace IngameScript
{
    // PB script enclosure rule:
    public partial class Program : MyGridProgram
    {
        public Program()
        {
            // TODO: construct kernel, register modules, set UpdateFrequency
        }

        public void Save()
        {
            // TODO: persist state
        }

        public void Main(string argument, UpdateType updateSource)
        {
            try
            {
                // TODO: dispatch into VIOS kernel/tick
                Echo("Hello from __NAME__!");
            }
            catch (System.Exception ex)
            {
                Echo("VIOS ERROR: " + ex.Message);
            }
        }
    }
}

