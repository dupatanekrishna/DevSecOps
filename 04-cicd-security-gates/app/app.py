from flask import Flask, request, jsonify
import os
import subprocess

app = Flask(__name__)

# Read secrets from the environment rather than hard-coding them.
LAB_SECRET = os.environ.get("LAB_SECRET")


@app.route("/")
def home():
    return jsonify(
        message="DevSecOps CI/CD Security Lab",
        status="running",
    )


@app.route("/calculate")
def calculate():
    expression = request.args.get("expression", "")

    # Intentionally insecure for SAST experimentation.
    # Semgrep/SonarQube should flag user-controlled eval().
    result = eval(expression)

    return jsonify(result=result)


@app.route("/command")
def command():
    command_input = request.args.get("cmd", "echo hello")

    # Intentionally insecure for SAST experimentation.
    # Do not copy this pattern into production code.
    result = subprocess.check_output(
        command_input,
        shell=True,
        text=True,
    )

    return jsonify(output=result)


if __name__ == "__main__":
    # debug=True is intentional so static scanners have another finding.
    app.run(
        host="0.0.0.0",
        port=8080,
        debug=True,
    )
