import asyncio
import logging

from app.realtime.manager import ConnectionManager, connection_manager, make_new_alerts_broadcaster


class _FakeWebSocket:
    def __init__(self):
        self.sent: list[dict] = []
        self.accepted = False
        self.raise_on_send = False

    async def accept(self):
        self.accepted = True

    async def send_json(self, message):
        if self.raise_on_send:
            raise RuntimeError("connection closed")
        self.sent.append(message)


def test_connect_accepts_and_registers_the_connection():
    manager = ConnectionManager()
    ws = _FakeWebSocket()
    asyncio.run(manager.connect(ws))
    assert ws.accepted is True
    assert ws in manager._connections


def test_disconnect_removes_the_connection():
    manager = ConnectionManager()
    ws = _FakeWebSocket()
    asyncio.run(manager.connect(ws))
    manager.disconnect(ws)
    assert ws not in manager._connections


def test_disconnect_of_an_unregistered_connection_does_not_raise():
    manager = ConnectionManager()
    ws = _FakeWebSocket()
    manager.disconnect(ws)  # never connected — must be a no-op, not an error


def test_broadcast_sends_the_message_to_every_connected_client():
    manager = ConnectionManager()
    ws1, ws2 = _FakeWebSocket(), _FakeWebSocket()
    asyncio.run(manager.connect(ws1))
    asyncio.run(manager.connect(ws2))
    asyncio.run(manager.broadcast({"type": "new_alerts", "alerts": []}))
    assert ws1.sent == [{"type": "new_alerts", "alerts": []}]
    assert ws2.sent == [{"type": "new_alerts", "alerts": []}]


def test_broadcast_skips_a_failed_client_without_stopping_delivery_to_others():
    manager = ConnectionManager()
    bad, good = _FakeWebSocket(), _FakeWebSocket()
    bad.raise_on_send = True
    asyncio.run(manager.connect(bad))
    asyncio.run(manager.connect(good))
    asyncio.run(manager.broadcast({"type": "new_alerts", "alerts": []}))
    assert good.sent == [{"type": "new_alerts", "alerts": []}]
    assert bad not in manager._connections


_MESSAGE = {"type": "new_alerts", "alerts": []}


class _GatedWebSocket(_FakeWebSocket):
    """A client whose send_json genuinely suspends until the test releases it.

    This is the whole point of the race tests below: `await send_json(...)` must
    be a REAL suspension point (as it is in production under transport-level
    backpressure from a slow/stalled client), so another task can be scheduled
    and mutate the connection registry while broadcast() sits inside its loop.
    Gated on asyncio.Events the test controls rather than any sleep duration, so
    the interleaving is deterministic rather than timing-dependent.
    """

    def __init__(self, release: asyncio.Event, entered: asyncio.Event):
        super().__init__()
        self._release = release
        # Set the instant send_json is entered, so the test can await proof
        # that broadcast() is genuinely parked INSIDE its iteration before
        # mutating the registry — no polling, no reliance on how many event
        # loop turns any particular Python/asyncio version happens to take.
        self._entered = entered

    async def send_json(self, message):
        self._entered.set()
        await self._release.wait()
        await super().send_json(message)


async def _assert_broadcast_survives_mutation(caplog, mutate):
    """Drive a broadcast that is parked mid-iteration, then mutate the registry.

    Two gated clients, not one, is what gives these tests their discriminating
    power. A set's iteration order is arbitrary, so with a single gated client
    there would be no client left to reach after the mutation — the broadcast
    would already be on its last element, and a live-set iteration would never
    get the chance to raise. With two, exactly one parks first, the mutation
    lands, and the iterator must still advance to the second: against a LIVE
    set that advance raises "RuntimeError: Set changed size during iteration",
    so the second client receives nothing at all.

    Both assertions matter. The delivery assertion catches the abort; the log
    assertion is what keeps this test honest given broadcast()'s own outer
    try/except, which deliberately swallows exceptions so production failures
    are logged rather than lost — without checking the log, a reverted snapshot
    fix would be silently absorbed by that guard and this test would still pass.
    """
    manager = ConnectionManager()
    release = asyncio.Event()
    entered = asyncio.Event()
    gated = [_GatedWebSocket(release, entered), _GatedWebSocket(release, entered)]
    for ws in gated:
        await manager.connect(ws)
    extra = await mutate(manager, when="before")

    with caplog.at_level(logging.ERROR, logger="app.realtime.manager"):
        broadcast_task = asyncio.create_task(manager.broadcast(_MESSAGE))
        await entered.wait()  # broadcast is now parked INSIDE its loop
        await mutate(manager, when="during", extra=extra)
        release.set()
        await broadcast_task  # must not raise

    # Every client connected when the broadcast began still received it — a
    # live-set iteration aborts partway and leaves the second one unsent.
    for ws in gated:
        assert ws.sent == [_MESSAGE]
    # ...and the outer guard never had to fire, i.e. nothing was swallowed.
    assert not [r for r in caplog.records if "Alert broadcast failed" in r.message]


def test_broadcast_survives_a_concurrent_connect_during_iteration(caplog):
    # Regression test for a real, empirically-reproduced bug: broadcast()
    # iterating the LIVE self._connections set. Another client connecting while
    # the broadcast is suspended mid-send raises "RuntimeError: Set changed size
    # during iteration", aborting delivery to every client not yet reached — and
    # silently, since production discards the returned Future.
    async def _connect(manager, when, extra=None):
        if when == "during":
            await manager.connect(_FakeWebSocket())

    asyncio.run(_assert_broadcast_survives_mutation(caplog, _connect))


def test_broadcast_survives_a_concurrent_disconnect_during_iteration(caplog):
    # The disconnect half of the same race. Kept separate rather than folded
    # into the connect case because it is a different set operation (discard,
    # shrinking the set) driven by a different production code path (the
    # WebSocket route's `finally`, on any client dropping) — and a set's size
    # changing DOWNWARD is what a future partial fix would most plausibly miss.
    async def _disconnect(manager, when, extra=None):
        if when == "before":
            doomed = _FakeWebSocket()
            await manager.connect(doomed)
            return doomed
        manager.disconnect(extra)

    asyncio.run(_assert_broadcast_survives_mutation(caplog, _disconnect))


def test_broadcast_logs_instead_of_failing_silently(caplog):
    # broadcast() is scheduled via run_coroutine_threadsafe with its Future
    # discarded, so an unhandled failure here is completely invisible in
    # production. The outer guard must convert any such failure into a log
    # record rather than a silently-dropped disaster alert.
    class _ExplodingConnections(set):
        def __iter__(self):
            raise RuntimeError("simulated registry failure")

    async def _run():
        manager = ConnectionManager()
        manager._connections = _ExplodingConnections()
        with caplog.at_level(logging.ERROR, logger="app.realtime.manager"):
            await manager.broadcast({"type": "new_alerts", "alerts": []})  # must not raise
        assert any("Alert broadcast failed" in r.message for r in caplog.records)

    asyncio.run(_run())


def test_make_new_alerts_broadcaster_noops_on_empty_list():
    async def _run():
        loop = asyncio.get_running_loop()
        broadcaster = make_new_alerts_broadcaster(loop)
        result = broadcaster([])
        assert result is None

    asyncio.run(_run())


def test_make_new_alerts_broadcaster_schedules_a_real_broadcast():
    async def _run():
        loop = asyncio.get_running_loop()
        ws = _FakeWebSocket()
        await connection_manager.connect(ws)
        try:
            broadcaster = make_new_alerts_broadcaster(loop)
            future = broadcaster([{"external_id": "x"}])
            await asyncio.wrap_future(future)
            assert ws.sent == [{"type": "new_alerts", "alerts": [{"external_id": "x"}]}]
        finally:
            connection_manager.disconnect(ws)

    asyncio.run(_run())
