[img]https://i.imgur.com/your-logo.png[/img]
[size=18][b]Viking Industries Operating System (VIOS)[/b][/size]
[i]by Viking Industries (Thorbergr) — MIT Licensed[/i]


[b]What is VIOS?[/b]
VIOS is an extensible in-game operating framework for Space Engineers Programmable Blocks. It provides a kernel, coroutine scheduler, message/event bus, LCD UI widgets, pooling/queuing utilities, and a module API for power, airlocks, cargo, production, and more.


[b]Highlights[/b]
[list]
[*] Coroutine + state machine scheduler (TIC/depth aware)
[*] LAN/WAN messaging via IGC (unicast/multicast/broadcast)
[*] LCD widgets: headers, footers, spinner, progress, 2D chart, lists, tables
[*] CustomData (MyIni) config; persistence; multi-screen layouts
[*] Module library + clean API for third-party extensions
[/list]


[b]Branding & Compatibility[/b]
[list]
[*] Core types are branded (e.g., [i]VIOSKernel[/i]); third-party modules can keep neutral class names.
[*] Use the badge: [i]Compatible with VIOS[/i] if your mod implements the public interfaces and protocol.
[*] You may change the network tag in CustomData (default: [i]VIOS[/i]).
[/list]


[b]License[/b]
MIT License — see the included LICENSE file.


[b]Links[/b]
[list]
[*] GitHub: [url]https://github.com/{{GITHUB_OWNER}}/{{GITHUB_REPO}}[/url]
[*] Issue Tracker: [url]https://github.com/{{GITHUB_OWNER}}/{{GITHUB_REPO}}/issues[/url]
[*] Discord (optional): [url]https://discord.gg/yourinvite[/url]
[/list]


[b]Installation[/b]
[list]
[*] Subscribe, reload world, place a Programmable Block.
[*] Load the VIOS script from your Workshop subscriptions.
[*] Configure via [code]Me.CustomData[/code] (see examples below).
[/list]


[b]Quick Config (CustomData)[/b]
[code]
[VIOS]
UpdateFrequency=Update10,Update100
TIC.Soft=30000
TIC.Hard=45000
Depth.Max=50
Network.Tag=VIOS


[Modules]
Enable=Power,ScreenMgr,Oxygen,Hydrogen,Door,Airlock,Cargo,Production
[/code]


[b]Badges[/b]
[list]
[*] ✅ Powered by VIOS (official kernel)
[*] ✅ Compatible with VIOS (interfaces & protocol)
[/list]


[i]Viking Industries and Viking Industries Operating System (VIOS) are names used to identify the original project by Thorbergr. See LICENSE and TRADEMARK for details.[/i]

