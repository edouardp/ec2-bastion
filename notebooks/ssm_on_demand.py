import marimo

__generated_with = "0.23.1"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo
    import boto3
    import os
    import asyncio

    return asyncio, boto3, mo, os


@app.cell
def _(mo, os):
    stack_name = mo.ui.dropdown(
        options=["ssm-on-demand", "ssm-on-demand-staging"],
        value="ssm-on-demand-staging",
        label="Stack name",
    )
    region = mo.ui.text(
        value=os.environ.get("AWS_REGION", "ap-southeast-2"),
        label="Region",
    )
    command = mo.ui.text_area(
        value="uname -a && cat /etc/os-release",
        label="Shell command to run",
    )
    mo.vstack([stack_name, region, command])
    return command, region, stack_name


@app.cell
def _(
    boto3,
    get_clients,
    get_stack_outputs,
    mo,
    region,
    stack_name,
):
    cf, lam, asg, ssm = get_clients(boto3, region.value)
    outputs = get_stack_outputs(cf, stack_name.value)
    start_fn_name = outputs["StartFunctionArn"]
    asg_name = outputs["AutoScalingGroupName"]
    env_name = outputs["Environment"]

    mo.md(f"**Lambda:** `{start_fn_name}`  \n**ASG:** `{asg_name}`")
    return asg, asg_name, env_name, lam, region, ssm, start_fn_name


@app.cell
def _(mo):
    go = mo.ui.run_button(label="🚀 Start instance & run command")
    go
    return (go,)


@app.cell
async def _(
    asg,
    asg_name,
    asyncio,
    command,
    go,
    lam,
    mo,
    run_command,
    ssm,
    start_fn_name,
    wait_for_instance,
    wait_for_ssm,
):
    mo.stop(not go.value, mo.md("*Click the button above to start.*"))

    with mo.status.spinner(title="Starting...") as sp:
        lam.invoke(FunctionName=start_fn_name, InvocationType="RequestResponse")

        sp.update(subtitle="Waiting for instance...")
        instance_id = await wait_for_instance(asg, asg_name, asyncio)
        if not instance_id:
            mo.stop(True, mo.callout("Timed out waiting for instance", kind="danger"))

        sp.update(subtitle=f"{instance_id} up. Waiting for SSM agent...")
        if not await wait_for_ssm(ssm, instance_id, asyncio):
            mo.stop(True, mo.callout(f"SSM agent on {instance_id} never registered", kind="danger"))

        sp.update(subtitle="Running command...")
        output = await run_command(ssm, instance_id, command.value, asyncio)

    if not output:
        mo.stop(True, mo.callout("Command timed out", kind="danger"))

    mo.vstack([
        mo.md(f"### ✅ Command on `{instance_id}`"),
        mo.md(f"**Status:** {output['Status']}"),
        mo.md("**stdout:**"),
        mo.plain_text(output.get("StandardOutputContent", "")),
        mo.md("**stderr:**"),
        mo.plain_text(output.get("StandardErrorContent", "")),
    ])
    return


@app.cell
def _():
    def get_clients(boto3, region):
        return (
            boto3.client("cloudformation", region_name=region),
            boto3.client("lambda", region_name=region),
            boto3.client("autoscaling", region_name=region),
            boto3.client("ssm", region_name=region),
        )

    def get_stack_outputs(cf, stack_name):
        return {
            o["OutputKey"]: o["OutputValue"]
            for o in cf.describe_stacks(StackName=stack_name)["Stacks"][0]["Outputs"]
        }

    def generate_ephemeral_key():
        import subprocess
        import tempfile
        key_dir = tempfile.mkdtemp()
        key_path = f"{key_dir}/key"
        subprocess.run(
            ["ssh-keygen", "-t", "ed25519", "-f", key_path, "-N", ""],
            check=True, capture_output=True,
        )
        return key_path, f"{key_path}.pub", key_dir

    def push_ssh_key(ec2ic, instance_id, pub_key_path):
        import boto3 as _boto3
        ec2 = _boto3.client("ec2")
        az = ec2.describe_instances(
            InstanceIds=[instance_id]
        )["Reservations"][0]["Instances"][0]["Placement"]["AvailabilityZone"]
        with open(pub_key_path) as f:
            pub_key = f.read()
        ec2ic.send_ssh_public_key(
            InstanceId=instance_id,
            InstanceOSUser="ec2-user",
            AvailabilityZone=az,
            SSHPublicKey=pub_key,
        )

    async def wait_for_instance(asg, asg_name, asyncio):
        for _ in range(60):
            groups = asg.describe_auto_scaling_groups(
                AutoScalingGroupNames=[asg_name]
            )["AutoScalingGroups"]
            instances = groups[0]["Instances"] if groups else []
            healthy = [i for i in instances if i["LifecycleState"] == "InService"]
            if healthy:
                return healthy[0]["InstanceId"]
            await asyncio.sleep(5)
        return None

    async def wait_for_ssm(ssm, instance_id, asyncio):
        for _ in range(24):
            try:
                info = ssm.describe_instance_information(
                    Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
                )
                if info["InstanceInformationList"]:
                    return True
            except Exception:
                pass
            await asyncio.sleep(5)
        return False

    async def run_command(ssm, instance_id, cmd, asyncio):
        send = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": [cmd]},
        )
        cmd_id = send["Command"]["CommandId"]
        for _ in range(30):
            await asyncio.sleep(2)
            result = ssm.get_command_invocation(
                CommandId=cmd_id, InstanceId=instance_id
            )
            if result["Status"] in ("Success", "Failed", "Cancelled", "TimedOut"):
                return result
        return None

    return (
        generate_ephemeral_key,
        get_clients,
        get_stack_outputs,
        push_ssh_key,
        run_command,
        wait_for_instance,
        wait_for_ssm,
    )


@app.cell
def _(mo):
    tunnel_btn = mo.ui.run_button(label="🔌 Start PG tunnel")
    tunnel_btn
    return (tunnel_btn,)


@app.cell
async def _(
    asg,
    asg_name,
    asyncio,
    boto3,
    env_name,
    generate_ephemeral_key,
    lam,
    mo,
    push_ssh_key,
    region,
    ssm,
    start_fn_name,
    tunnel_btn,
    wait_for_instance,
    wait_for_ssm,
):
    import json
    import subprocess

    mo.stop(not tunnel_btn.value, mo.md("*Click above to start the PG tunnel.*"))

    with mo.status.spinner(title="Starting tunnel...") as _sp:
        # Start instance
        lam.invoke(FunctionName=start_fn_name, InvocationType="RequestResponse")
        _sp.update(subtitle="Waiting for instance...")
        _instance_id = await wait_for_instance(asg, asg_name, asyncio)
        if not _instance_id:
            mo.stop(
                True, mo.callout("Timed out waiting for instance", kind="danger")
            )

        _sp.update(subtitle="Waiting for SSM agent...")
        if not await wait_for_ssm(ssm, _instance_id, asyncio):
            mo.stop(True, mo.callout("SSM agent never registered", kind="danger"))

        # Generate ephemeral key and push via EC2 Instance Connect
        _sp.update(subtitle="Pushing ephemeral SSH key...")
        _key_path, _pub_path, _key_dir = generate_ephemeral_key()
        ec2ic = boto3.client("ec2-instance-connect", region_name=region.value)
        push_ssh_key(ec2ic, _instance_id, _pub_path)

        # Get RDS credentials
        _sp.update(subtitle="Fetching RDS credentials...")
        sm = boto3.client("secretsmanager", region_name=region.value)
        secret = json.loads(
            sm.get_secret_value(SecretId=f"{env_name}/aurora/master")["SecretString"]
        )

        # Start SSH tunnel
        _sp.update(subtitle="Opening SSH tunnel...")
        tunnel_proc = subprocess.Popen(
            [
                "ssh",
                "-i",
                _key_path,
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
                "-o",
                f"ProxyCommand=aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region {region.value}",
                "-N",
                "-L",
                f"5432:{secret['host']}:5432",
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
        f"✅ Tunnel open (PID {tunnel_proc.pid}) → `{secret['host']}:5432`\n\n"
        f"DB: `{secret['dbname']}` | User: `{secret['username']}`",
        kind="success",
    )
    return (pg_url,)


@app.cell
def _(mo, pg_url):
    import sqlalchemy

    engine = sqlalchemy.create_engine(pg_url)
    mo.sql(engine=engine, query="SELECT current_database();")
    mo.callout("✅ SQL engine ready — use `mo.sql()` cells to query.", kind="info")
    return (engine,)


@app.cell
def _():
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT current_database(), current_user, inet_server_addr(), inet_server_port();
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""

        """,
        engine=engine
    )
    return


if __name__ == "__main__":
    app.run()
