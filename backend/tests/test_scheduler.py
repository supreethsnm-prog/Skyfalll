import threading
import time

from app.scheduler import IngestionScheduler


def test_runs_job_repeatedly_at_the_given_interval():
    call_times = []
    lock = threading.Lock()

    def job():
        with lock:
            call_times.append(time.monotonic())
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("test-job", job, 0.05)])
    try:
        time.sleep(0.22)  # should allow ~4 calls at a 0.05s interval
    finally:
        scheduler.stop()

    with lock:
        count = len(call_times)
    assert count >= 3  # timing-tolerant lower bound, not an exact count


def test_stop_halts_further_calls():
    call_count = {"n": 0}
    lock = threading.Lock()

    def job():
        with lock:
            call_count["n"] += 1
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("test-job", job, 0.02)])
    time.sleep(0.05)
    scheduler.stop()
    with lock:
        count_at_stop = call_count["n"]
    time.sleep(0.1)  # give it time to prove it did NOT keep running
    with lock:
        count_after_wait = call_count["n"]

    assert count_after_wait == count_at_stop


def test_a_failing_job_does_not_stop_the_scheduler_or_crash():
    call_count = {"n": 0}
    lock = threading.Lock()

    def flaky_job():
        with lock:
            call_count["n"] += 1
            current = call_count["n"]
        if current == 1:
            raise RuntimeError("simulated transient failure")
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("flaky-job", flaky_job, 0.03)])
    try:
        time.sleep(0.15)
    finally:
        scheduler.stop()

    with lock:
        count = call_count["n"]
    assert count >= 2  # it kept running after the first call raised


def test_multiple_jobs_run_independently():
    calls = {"a": 0, "b": 0}
    lock = threading.Lock()

    def job_a():
        with lock:
            calls["a"] += 1
        return 1

    def job_b():
        with lock:
            calls["b"] += 1
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("job-a", job_a, 0.03), ("job-b", job_b, 0.03)])
    try:
        time.sleep(0.15)
    finally:
        scheduler.stop()

    with lock:
        a_count, b_count = calls["a"], calls["b"]
    assert a_count >= 2
    assert b_count >= 2


def test_stop_is_safe_to_call_when_nothing_was_started():
    scheduler = IngestionScheduler()
    scheduler.stop()  # must not raise
