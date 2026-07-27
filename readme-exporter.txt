可以。最简单的方案是写一个独立的 Node.js Exporter。它同时做两件事：

1. 增量读取 Besu 日志，解析当前 QBFT Round。
2. 定期读取 `/tmp/config.toml`，检查 `sync-mode` 是否为 `FULL`。
3. 在 `/metrics` 暴露 Prometheus 指标。

Besu 当前源码中的关键日志是：

```text
Starting new round 0
Starting new round 1
Starting new round 2
```

对应源码：

```java
LOG.debug("Starting new round {}", roundNumber);
```

因此，这条日志只有在 Besu 开启 `DEBUG` 日志级别时才能看到。

发生 Round 超时或收到足够的 RoundChange 消息时，还可能看到：

```text
Round has expired or changing based on RC quorum, creating PreparedCertificate and notifying peers. round=...
```

以及：

```text
Round change from 0x...: block 1234, round 1
```

Besu 会在当前 Round 超时后启动下一轮，也会在收到足够的 RoundChange 消息时切换 Round。

对于监控“当前 Round”，最可靠的匹配是：

```regex
Starting new round\s+(\d+)
```

因为 `Round change from ...` 表示收到一条 RoundChange 消息，不一定表示本节点已经真正切换 Round。

## Exporter 代码

创建目录：

```bash
mkdir -p /opt/besu-custom-exporter
cd /opt/besu-custom-exporter
```

创建文件：

```bash
vi besu-exporter.js
```

写入代码

## 启动 Exporter

先确认 Node.js：

```bash
node --version
```

启动时指定 Besu 日志路径：

```bash
BESU_LOG_FILE=/var/log/besu/besu.log \
BESU_CONFIG_FILE=/tmp/config.toml \
node /opt/besu-custom-exporter/besu-exporter.js
```

正常输出：

```text
Besu custom exporter started
Metrics: http://0.0.0.0:9200/metrics
Health:  http://0.0.0.0:9200/health
Log file: /var/log/besu/besu.log
Config:   /tmp/config.toml
```

检查：

```bash
curl http://127.0.0.1:9200/metrics
```

可能返回：

```text
# HELP besu_custom_qbft_current_round Current QBFT round parsed from Besu logs
# TYPE besu_custom_qbft_current_round gauge
besu_custom_qbft_current_round 1

# HELP besu_custom_qbft_round_change_total Number of observed transitions to QBFT rounds greater than zero
# TYPE besu_custom_qbft_round_change_total counter
besu_custom_qbft_round_change_total 3

# HELP besu_custom_config_sync_mode_full Whether sync-mode in the Besu configuration is FULL: 1 means FULL, 0 means not FULL
# TYPE besu_custom_config_sync_mode_full gauge
besu_custom_config_sync_mode_full 1
```

检查健康状态：

```bash
curl http://127.0.0.1:9200/health
```

结果：

```json
{
  "status": "UP",
  "logReadable": true,
  "configReadable": true,
  "currentRound": 0,
  "syncModeFull": true
}
```

## 确认日志里是否存在 Round 信息

先执行：

```bash
grep -E \
'Starting new round|Round change from|Round has expired' \
/var/log/besu/besu.log |
tail -50
```

如果完全没有结果，很可能是 Besu 当前不是 DEBUG 日志级别。

你需要确保能看到类似：

```text
DEBUG ... Starting new round 0
DEBUG ... Starting new round 1
DEBUG ... Round change from 0xabc...: block 1234, round 1
```

`Starting new round`、`Round change from` 和 Round 超时信息在 Besu 源码中都使用 `DEBUG` 日志级别。

## 配置 Prometheus

在 `prometheus.yml` 中增加：

```yaml
scrape_configs:
  - job_name: "besu-custom-exporter"
    scrape_interval: 5s
    static_configs:
      - targets:
          - "10.20.30.50:9200"
```

重新加载 Prometheus：

```bash
curl -X POST \
  http://127.0.0.1:9090/-/reload
```

或者重启：

```bash
sudo systemctl restart prometheus
```

查询：

```promql
up{job="besu-custom-exporter"}
```

应返回：

```text
1
```

## Grafana 告警查询

### 当前 Round 超过 0

```promql
besu_custom_qbft_current_round > 0
```

建议持续 10 秒或 30 秒再触发，避免短暂 Round Change 造成太多通知。

### 5 分钟内发生 Round Change

```promql
increase(
  besu_custom_qbft_round_change_total[5m]
) > 0
```

### 5 分钟内频繁 Round Change

例如 5 分钟超过 3 次：

```promql
increase(
  besu_custom_qbft_round_change_total[5m]
) > 3
```

### sync-mode 不是 FULL

```promql
besu_custom_config_sync_mode_full == 0
```

建议同时确认文件可读：

```promql
besu_custom_config_file_readable == 1
and
besu_custom_config_sync_mode_full == 0
```

### 配置文件无法读取

```promql
besu_custom_config_file_readable == 0
```

### 日志文件无法读取

```promql
besu_custom_log_file_readable == 0
```

## 一个需要注意的问题

`besu_custom_qbft_current_round` 是从日志得到的“最近一次看到的 Round”。

当新区块进入 Round 0 时，日志会更新为：

```text
Starting new round 0
```

因此指标会恢复到：

```text
besu_custom_qbft_current_round 0
```

但是，如果日志级别被修改、日志文件停止写入，或者 Exporter 没有权限读取日志，这个值可能一直停留在旧的 Round。你应同时监控：

```promql
time()
-
besu_custom_last_log_event_timestamp_seconds
```

不过，网络正常时不一定每个区块都会立刻产生你匹配的日志。更稳妥的告警组合是：

```promql
besu_custom_qbft_current_round > 0
```

加上 Besu 原生的停止出块告警：

```promql
time() - besu_blockchain_chain_head_timestamp > 15
```

Round 较高并且节点停止出块时，才提升为 P0。
