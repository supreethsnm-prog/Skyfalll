import asyncio

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
