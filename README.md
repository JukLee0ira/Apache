# Grafana Besu priority alerts

This package provisions eight Grafana-managed alert rules:

1. Host CPU > 80% for 5 minutes
2. Besu process CPU > 0.8 CPU cores for 5 minutes
3. Filesystem usage > 80% for 5 minutes
4. CPU I/O wait > 10% for 5 minutes
5. Host memory usage > 85% for 5 minutes
6. Besu JVM heap usage > 85% of max heap for 5 minutes
7. Combined server network traffic > 100 MiB/s for 5 minutes
8. Established TCP connections > 1000 for 5 minutes

## 1. Edit placeholders

Open both YAML files and replace:

- `PROMETHEUS_DS_UID` with the UID of the Prometheus data source in Grafana.
- `ALERT_EMAIL_TO` with one or more recipients. Separate multiple addresses with semicolons.

The Prometheus UID is shown in Grafana at **Connections -> Data sources -> Prometheus**. It is also present in the data-source URL.

The rules assume these Prometheus job labels:

- node exporter: `job` matches `node-exporter.*`
- Besu: `job` matches `besu.*`

Change those two regular expressions when your `prometheus.yml` uses different job names.

## 2. Configure SMTP

For a package installation, edit `/etc/grafana/grafana.ini`:

```ini
[smtp]
enabled = true
host = smtp.example.com:587
user = monitoring@example.com
password = CHANGE_ME
from_address = monitoring@example.com
from_name = Grafana Besu Alerts
skip_verify = false
startTLS_policy = MandatoryStartTLS
```

For Docker or Docker Compose, copy the values from `grafana-smtp.env.example` into the Grafana container environment.

## 3. Import by file provisioning

### Linux package installation

```bash
sudo cp 01-alert-rules.yml /etc/grafana/provisioning/alerting/
sudo cp 02-email-contact-point.yml /etc/grafana/provisioning/alerting/
sudo systemctl restart grafana-server
```

### Docker Compose

Mount the directory into Grafana:

```yaml
services:
  grafana:
    image: grafana/grafana:latest
    volumes:
      - ./grafana-besu-alerts:/etc/grafana/provisioning/alerting:ro
    environment:
      GF_SMTP_ENABLED: "true"
      GF_SMTP_HOST: "smtp.example.com:587"
      GF_SMTP_USER: "monitoring@example.com"
      GF_SMTP_PASSWORD: "CHANGE_ME"
      GF_SMTP_FROM_ADDRESS: "monitoring@example.com"
      GF_SMTP_FROM_NAME: "Grafana Besu Alerts"
      GF_SMTP_STARTTLS_POLICY: "MandatoryStartTLS"
```

Then run:

```bash
docker compose up -d --force-recreate grafana
```

Grafana can also reload files without a full restart:

```bash
curl -X POST -u admin:YOUR_PASSWORD \
  http://localhost:3000/api/admin/provisioning/alerting/reload
```

## 4. Verify before relying on email

In Grafana:

1. Open **Alerting -> Alert rules** and confirm the folder `Besu Infrastructure Alerts` exists.
2. Open **Alerting -> Contact points -> besu-email** and send a test notification.
3. Open Prometheus Explore and run each PromQL expression. A missing series usually means the `job` label or metric name differs.
4. Temporarily lower one threshold, wait for the `for: 5m` period, and confirm both firing and resolved emails.

## Important notes

- File-provisioned resources are read-only in the Grafana UI. Edit the YAML and reload or restart Grafana.
- `02-email-contact-point.yml` provisions the complete notification-policy tree and routes the root policy to `besu-email`. It can overwrite existing policies. If you already have policies, merge the `besu-email` route into your existing exported policy file instead of copying this file directly.
- The Besu CPU expression returns CPU cores used. `0.8` means 80% of one core. A busy multi-threaded Besu process can exceed `1.0`. Tune this threshold after observing the normal baseline.
- Besu JVM metric names changed in newer releases. The heap rule supports both the older `jvm_memory_bytes_*` and newer `jvm_memory_*_bytes` names.
- Network and connection thresholds are starting values. Set them from your normal baseline and link capacity.
