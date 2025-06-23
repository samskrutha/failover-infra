# Failover Infrastructure with Self Healing and Monitoring

The project sets up a simulated hybrid environment (on-prem and cloud) using Docker, all provisioned and managed by Terraform. It features a simple REST API with automatic failover handled by HAProxy. The entire stack is monitored by Prometheus, with alerts sent via email through Alertmanager.

---

## Instructions

To run this project, you need to have Terraform and Docker installed.

### Local Docker Configuration (Important)

Terraform needs to know how to connect to your local Docker daemon.

You must create a file named `terraform.tfvars` in the root of the project to provide this path.

First, find your Docker daemon socket path by running:

```bash
docker context ls
````

Look for the active context (marked with `*`) and copy the path from the **DOCKER ENDPOINT** column.

Now, create the `terraform.tfvars` file and add the path:

```hcl
# terraform.tfvars
docker_host_path = "unix:///path/to/your/docker.sock"
```

> **Note:** This `terraform.tfvars` file should **not** be committed to version control.

---

### Email Alert Configuration

Before running these please configure your Gmail account in the `alertmanager.yml` file. You need to get the app password and then store it in the `alertmanager` folder as `password.txt`.

Also remember to enter the proper receiver's address in the `alertmanager.yml` file.

#### `alertmanager/alertmanager.yml` Example:

```yaml
global:
  smtp_from: 'from_address@gmail.com' 
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'username@gmail.com' 
  smtp_auth_password_file: '/etc/alertmanager/password.txt' 
route:
  receiver: 'email-notifications'
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
receivers:
- name: 'email-notifications'
  email_configs:
    - to: 'to_address@gmail.com' 
      send_resolved: true
```

#### `alertmanager/password.txt`

```
xxxxxxxxxxxxxxxx
```

> **Note:** Remember to add `alertmanager/password.txt` to your `.gitignore` file.

---

### Environment Simulation

Please also mention that for this assignment I have used different ports for on-prem and cloud to simulate those environments.

* The **on-prem** service is exposed on host port `5000`
* The **cloud** service is exposed on host port `5001`

---

## Deployment

First, you have to clone this project to your local machine and then run the following:

```bash
# Initialize Terraform
terraform init

# Apply the configuration to build and run all containers
terraform apply
```

---

## Testing Failover, Alerting, and Recovery

To test the failover service, you need to:

### Step 1: Stop the on-prem service

```bash
docker stop api-onprem
```

* Check Prometheus alerts at `http://localhost:9090` after 1 minute.
* Also check Alertmanager UI at `http://localhost:9093`.
* You should receive a `[FIRING]` notification in your email.

### Step 2: Start the on-prem service

```bash
docker start api-onprem
```

* A few moments later, you should receive a `[RESOLVED]` email notification.

---

## Architecture

- Health Checks: The check keyword on this line ```server onprem api-onprem:5000 maxconn 32 check...``` is the "code" that tells HAProxy to continuously send health checks to the on-prem server to see if it's alive.

- The "code" for this automatic failover is these two lines in the current haproxy/haproxy.cfg file:
```
backend api_backend
    server onprem api-onprem:5000 check resolvers docker_dns
    server cloud api-cloud:5000 check backup resolvers docker_dns
```
The check keyword enables the health check on the onprem server.

The backup keyword tells HAProxy: "If the onprem server fails its health check, automatically send all traffic to this cloud server instead."

- Previousl I had an external healthcheck script (Below) and haproxy template which I then replaced with the above configuration:

```
import time
import requests
import subprocess

ONPREM = "http://localhost:5000/health"
CONFIG_TEMPLATE = "haproxy/haproxy.cfg.template"
ACTIVE_CONFIG = "/usr/local/etc/haproxy/haproxy.cfg"

def is_onprem_up():
    try:
        response = requests.get(ONPREM, timeout=2)
        return response.status_code == 200
    except:
        return False

def update_backend(backend):
    with open(CONFIG_TEMPLATE, 'r') as f:
        template = f.read()
    new_config = template.replace("{{BACKEND}}", backend).strip() + '\n'
    with open("haproxy/haproxy.cfg", 'w') as f:
        f.write(new_config)
    subprocess.run(["docker", "cp", "haproxy/haproxy.cfg", "haproxy-server:/usr/local/etc/haproxy/haproxy.cfg"])
    subprocess.run(["docker", "restart", "haproxy-server"])

def monitor():
    last_status = None
    while True:
        up = is_onprem_up()
        if up and last_status != "onprem":
            print("On-Prem is UP. Routing traffic to onprem.")
            update_backend("onprem")
            last_status = "onprem"
        elif not up and last_status != "cloud":
            print("On-Prem is DOWN. Routing traffic to cloud.")
            update_backend("cloud")
            last_status = "cloud"
        time.sleep(10)

if __name__ == "__main__":
    monitor()
```

- The whole idea for the above script was to monitor and then change the haproxy config to onprem or cloud based on the failure but the current project without this script made more sense to me.

---

## CI/CD

I have also integrated the CI/CD GitHub Actions workflow in `.github/workflows/main.yml`.

```yaml
name: 'Terraform CI/CD'

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  terraform:
    name: 'Terraform'
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate
```

---

## Monitoring & Observability

I have provisioned Grafana as well. The dashboards can be added as yml files in the repo and then provisioned through terraform. This can be considered as an improvement. With Kubernetes, the dashboards can be added via config maps and gitops.

---

## Improvements

- Please note that I can also provision the infrastructure on the cloud via terraform instead of locally for testing. 
- I have kept the code very simple for the assignment. 
- I have referenced my old projects and some of the open source repos from Github to complete this task.
- The code can still be refactored and made modular if necessary

---

## Feedback

I look forward to hearing your feedback and suggestions for improvements. Please feel free to reach out. 