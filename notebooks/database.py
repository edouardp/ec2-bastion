import marimo

__generated_with = "0.23.1"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo
    import boto3
    import asyncio
    import json
    import os
    import subprocess
    import tempfile

    return asyncio, boto3, json, mo, os, subprocess, tempfile


@app.cell
def _(mo, os):
    STACKS = {
        "staging": {"ec2": "ssm-on-demand-staging", "secret": "staging/aurora/master"},
        "prod": {"ec2": "ssm-on-demand", "secret": "prod/aurora/master"},
    }

    env = mo.ui.dropdown(options=["staging", "prod"], value="staging", label="Environment")
    region = mo.ui.text(
        value=os.environ.get("AWS_REGION", "ap-southeast-2"),
        label="Region",
    )
    connect_btn = mo.ui.run_button(label="🔌 Connect to database")
    mo.vstack([env, region, connect_btn])
    return STACKS, connect_btn, env, region


@app.cell(hide_code=True)
async def _(
    STACKS,
    asyncio,
    boto3,
    connect_btn,
    env,
    json,
    mo,
    os,
    region,
    subprocess,
    tempfile,
):
    mo.stop(not connect_btn.value, mo.md("*Select environment and click Connect.*"))

    stack = STACKS[env.value]
    cf = boto3.client("cloudformation", region_name=region.value)
    asg_client = boto3.client("autoscaling", region_name=region.value)
    ssm = boto3.client("ssm", region_name=region.value)
    lam = boto3.client("lambda", region_name=region.value)

    outputs = {
        o["OutputKey"]: o["OutputValue"]
        for o in cf.describe_stacks(StackName=stack["ec2"])["Stacks"][0]["Outputs"]
    }

    with mo.status.spinner(title="Connecting...") as _sp:
        # Start instance
        lam.invoke(FunctionName=outputs["StartFunctionArn"], InvocationType="RequestResponse")

        # Wait for instance
        _sp.update(subtitle="Waiting for instance...")
        _instance_id = None
        for _ in range(60):
            groups = asg_client.describe_auto_scaling_groups(
                AutoScalingGroupNames=[outputs["AutoScalingGroupName"]]
            )["AutoScalingGroups"]
            healthy = [i for i in groups[0]["Instances"] if i["LifecycleState"] == "InService"]
            if healthy:
                _instance_id = healthy[0]["InstanceId"]
                break
            await asyncio.sleep(5)
        if not _instance_id:
            mo.stop(True, mo.callout("Timed out waiting for instance", kind="danger"))

        # Wait for SSM
        _sp.update(subtitle="Waiting for SSM agent...")
        for _ in range(24):
            info = ssm.describe_instance_information(
                Filters=[{"Key": "InstanceIds", "Values": [_instance_id]}]
            )
            if info["InstanceInformationList"]:
                break
            await asyncio.sleep(5)
        else:
            mo.stop(True, mo.callout("SSM agent never registered", kind="danger"))

        # SSH key
        _sp.update(subtitle="Fetching credentials...")
        _env_name = outputs["Environment"]
        _key = ssm.get_parameter(
            Name=f"/on-demand-ec2/{_env_name}/ssh/current/private",
            WithDecryption=True,
        )["Parameter"]["Value"]
        _key_file = tempfile.NamedTemporaryFile(mode="w", suffix=".pem", delete=False)
        _key_file.write(_key)
        _key_file.close()
        os.chmod(_key_file.name, 0o600)

        # RDS credentials
        sm = boto3.client("secretsmanager", region_name=region.value)
        secret = json.loads(
            sm.get_secret_value(SecretId=stack["secret"])["SecretString"]
        )

        # SSH tunnel
        _sp.update(subtitle="Opening tunnel...")
        tunnel_proc = subprocess.Popen(
            [
                "ssh", "-i", _key_file.name,
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", f"ProxyCommand=aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region {region.value}",
                "-N", "-L", f"5432:{secret['host']}:5432",
                f"ec2-user@{_instance_id}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        await asyncio.sleep(3)
        if tunnel_proc.poll() is not None:
            mo.stop(True, mo.callout("SSH tunnel failed to start", kind="danger"))

    pg_url = f"postgresql://{secret['username']}:{secret['password']}@127.0.0.1:5432/{secret['dbname']}"

    mo.callout(
        f"✅ Connected to **{env.value}** → `{secret['host']}`\n\n"
        f"DB: `{secret['dbname']}` | User: `{secret['username']}`",
        kind="success",
    )
    return (pg_url,)


@app.cell
def _(mo, pg_url):
    import sqlalchemy

    engine = sqlalchemy.create_engine(pg_url)
    mo.sql(engine=engine, query="SELECT current_database();")
    return


@app.cell
def _():
    return


if __name__ == "__main__":
    app.run()
