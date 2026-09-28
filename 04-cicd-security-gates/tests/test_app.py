import os
import sys

sys.path.insert(
    0,
    os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "../app",
        )
    ),
)

from app import app


def test_home():
    client = app.test_client()

    response = client.get("/")

    assert response.status_code == 200

    data = response.get_json()

    assert data["status"] == "running"
    assert data["message"] == "DevSecOps CI/CD Security Lab"


def test_calculate():
    client = app.test_client()

    response = client.get("/calculate?expression=2%2B2")

    assert response.status_code == 200

    data = response.get_json()

    assert data["result"] == 4
