"""Check CI orchestration failure handling without requiring Docker or live APIs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("backend_tasks", Path(__file__).resolve().parents[1] / "tasks.py")
tasks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tasks)


class CITaskTests(unittest.TestCase):
    def test_rejects_unknown_check_before_building(self):
        with patch.object(tasks, "docker_build_all") as build:
            with self.assertRaises(ValueError):
                tasks.ci_check.body(Mock(), check="shard-99")
            build.assert_not_called()

    def test_http_failure_keeps_logs_and_cleans_stack(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(tasks, "ROOT", Path(directory)), \
             patch.object(tasks, "docker_blackbox_up"), \
             patch.object(tasks, "docker_blackbox_test", side_effect=RuntimeError("failed suite")), \
             patch.object(tasks, "_compose_run", return_value=Mock(stdout="server log", stderr="")) as compose:
            with self.assertRaisesRegex(RuntimeError, "failed suite"):
                tasks.ci_check.body(Mock(), check="http", build=False)
            self.assertEqual(compose.call_args_list[-1].args[0], ["down", "-v", "--remove-orphans"])
            self.assertEqual((Path(directory) / "e2e-artifacts/ci/http.log").read_text(), "server log")

    def test_follow_uses_isolated_compose_stack(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(tasks, "ROOT", Path(directory)), \
             patch.object(tasks, "docker_blackbox_follow_up") as start, \
             patch.object(tasks, "docker_blackbox_follow_test") as run, \
             patch.object(tasks, "_compose_run", return_value=Mock(stdout="", stderr="")) as compose:
            context = Mock()
            tasks.ci_check.body(context, check="follow", build=False)
            start.assert_called_once_with(context, build=False)
            run.assert_called_once_with(context)
            self.assertEqual(compose.call_args.kwargs["compose_file"], tasks.BLACKBOX_FOLLOW_COMPOSE_FILE)

    def test_shard_index_is_forwarded_without_rebuilding(self):
        with patch.object(tasks, "docker_test_shard") as shard:
            context = Mock()
            tasks.ci_check.body(context, check="shard-8", build=False)
            shard.assert_called_once_with(context, node_index=8, build=False)


if __name__ == "__main__":
    unittest.main()
