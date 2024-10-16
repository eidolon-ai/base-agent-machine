from pathlib import Path

import pytest
from eidolon_ai_sdk.system.resources.resources_base import load_resources
from eidolon_ai_sdk.test_utils.machine import TestMachine
from eidolon_ai_sdk.test_utils.server import serve_thread
from eidolon_ai_sdk.test_utils.vcr import vcr_patch


@pytest.fixture(scope='module')
def vcr_config():
    return dict(
        ignore_localhost=True,
        filter_headers=[('authorization', '*****')],
    )


@pytest.fixture(scope="session")
def machine(tmp_path_factory):
    return TestMachine(tmp_path_factory.mktemp("test_utils_storage"))


@pytest.fixture(scope="session", autouse=True)
def server(machine):
    resources = load_resources([Path(__file__).parent.parent / "eidolon_resources"])
    with serve_thread([machine, *resources]):
        yield


@pytest.fixture(autouse=True)
def state_manager(request, machine):
    test_name = request.node.name
    machine.reset_state()
    with vcr_patch(test_name):
        yield
    machine.reset_state()
