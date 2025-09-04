# Task T-003 — Message Router (Local + IGC)

**Mode:** CODE-SKELETON • **Targets:** MDK²-SE, C# 6, netframework48

## Goal

Implement a lightweight message/event bus with unified local dispatch and IGC (WAN/LAN) forwarding.

## Scope

- Types: `VIOSAddress` (struct), `VIOSPacket` (struct), `VIOSMessageRouter` (class), `IMessageHandler`.
- Addressing: localhost (Me), LAN (connected grids), WAN (separate grids) via IGC tag (default `VIOS`, configurable via `CustomData`).
- Modes: unicast, multicast, broadcast.
- Queues: bounded, drop‑oldest on overflow; integrate with `CoroutineScheduler` for draining.
- Handlers: modules register endpoints by string key (`vendor.module.endpoint`).

## Constraints

- PB whitelist only; strings as payloads (compact, delimited or INI) — no heavy serializers.
- No per‑message allocations beyond a reusable packet.
- Respect TIC/depth budgets while dispatching.

## Deliverables

- `Mixins/VIOS.Core/Messaging.cs`: address/packet/router + registration API.
- `VIOSKernel` wiring: drain local queue, then IGC inbox, then scheduled sends; configurable `Network.Tag`.
- Demo: module subscribes to `Power.Status?` and returns `Power.Status!` with summary text.

## Acceptance Criteria

- Local loopback works with no IGC configured.
- With IGC enabled, packets publish under configured tag.
- Overflows drop oldest safely and increment a counter.
- Passes architecture checks and builds Release.

## References

- `docs/architecture/VIOS-Architecture.md` (Message/Event Handling)
