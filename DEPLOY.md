# 部署指南 - Ethereum RPC Filter

## 环境要求

### 必需软件

| 软件 | 版本 | 用途 |
|------|------|------|
| **Docker** | 20.10+ | 容器运行时 |
| **Docker Compose** | 1.29+ | 服务编排 |
| **Git** | 2.0+ | 版本控制 |

### 可选工具

| 工具 | 用途 |
|------|------|
| `curl` | API 测试 |
| `python3` | JSON 格式化输出 |
| `lsof` | 端口冲突检查 |

### 快速验证安装

```bash
docker --version
# 预期: Docker version 20.10.x

docker-compose --version
# 预期: Docker Compose version 1.29.x

git --version
# 预期: git version 2.x.x
```

---

## 环境版本说明

### 当前项目使用的版本

| 组件 | 版本 | 说明 |
|------|------|------|
| **Apache** | 2.4.x | Debian Bookworm 版本 |
| **Lua** | 5.1.x | Apache Lua 模块版本 |
| **Lua-cjson** | 2.1.x | JSON 编解码库 |
| **Python (Mock Server)** | 3.11-slim | 后端 Mock RPC 服务 |
| **Debian** | bookworm-slim | 基础镜像 |

### 版本兼容性说明

- **Lua 5.1** 是 Apache `mod_lua` 模块官方支持的版本
- 脚本使用 Lua 5.1 语法，不支持 Lua 5.2+ 的新特性
- Apache 2.4.x 模块路径可能与旧版本不同，本配置使用 Debian 标准路径

---

## 一、在 GitHub 仓库中下载代码

### 方法 1: Git Clone（推荐）

```bash
# 克隆仓库
git clone https://github.com/JukLee0ira/Apache.git

# 进入项目目录
cd Apache
```

### 方法 2: 下载 ZIP

1. 访问: https://github.com/JukLee0ira/Apache
2. 点击绿色 "Code" 按钮
3. 选择 "Download ZIP"
4. 解压到本地目录

---

## 二、快速启动（3 步完成）

### 步骤 1: 一键启动

```bash
cd /path/to/Apache

# 方式 A: 使用启动脚本（推荐）
./start.sh

# 方式 B: 直接使用 Docker Compose
docker-compose up -d
```

### 步骤 2: 验证启动状态

```bash
# 使用状态检查脚本
./status.sh

# 或手动检查
curl http://localhost:8888/health
# 预期输出: OK
```

### 步骤 3: 运行测试

```bash
# 完���测试套件（25 项测试）
./test/comprehensive_test.sh

# 或单独测试
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**预期成功输出:**
```json
{"jsonrpc": "2.0", "id": 1, "result": "0x10d4f"}
```

---

## 三、配置文件说明

### 核心配置文件

| 文件 | 说明 | 修改后是否需重启 |
|------|------|----------------|
| `config/whitelist.json` | 白名单配置（地址、方法） | **是** - 需重启 Apache |
| `apache/conf/sites-enabled/rpc-proxy.conf` | Apache 虚拟主机配置 | **是** - 需重建镜像 |
| `scripts/rpc_proxy.lua` | 过滤逻辑脚本 | **是** - 需重启 Apache |

### 修改白名单配置

```bash
# 编辑配置文件
vim config/whitelist.json

# 重启服务使配置生效
./restart.sh
# 或: docker-compose restart apache-proxy
```

---

## 四、服务管理命令

### 启动服务
```bash
./start.sh                    # 推荐，带健康检查
docker-compose up -d          # Docker Compose 方式
```

### 停止服务
```bash
./stop.sh
docker-compose down
```

### 重启服务
```bash
./restart.sh                  # 推荐，先停止再启动
docker-compose restart apache-proxy   # 仅重启代理
docker-compose restart ethereum-rpc-mock  # 仅重启 Mock 服务
```

### 查看状态
```bash
./status.sh                   # 推荐，显示状态、健康检查、日志
docker-compose ps             # 容器状态
curl http://localhost:8888/health  # 健康检查端点
```

### 查看日志
```bash
# 实时查看代理日志
docker logs -f apache-rpc-proxy

# 实时查看 Mock 日志
docker logs -f ethereum-rpc-mock

# 查看最近 N 行
docker logs --tail 100 apache-rpc-proxy
```

---

## 五、测试验证

### 快速验证测试（5 分钟）

运行完整测试套件:
```bash
./test/comprehensive_test.sh
```

**测试项包括:**
- ✓ 服务健康检查
- ✓ 白名单方法测试（4 个方法）
- ✓ 白名单地址测试（2 个地址）
- ✓ 非白名单方法拦截（4 个方法）
- ✓ 非白名单地址拦截（2 个地址）
- ✓ 响应内容验证
- ✓ 错误处理测试
- ✓ 日志一致性检查

预期输出: `All passed (25/25)` 或所有测试项显示 `[PASS]`

### 手动测试命令

```bash
# 1. 健康检查
curl http://localhost:8888/health

# 2. 白名单方法测试（应通过）
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 3. 非白名单方法测试（应被拦截）
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg","0x1234"],"id":1}'
# 预期: HTTP 403 Forbidden

# 4. 查看拦截记录
curl http://localhost:8545/blocked | python3 -m json.tool
```

---

## 六、故障排查

### 端口冲突

**问题:** 端口 8888 或 8545 已被占用

**排查:**
```bash
lsof -i :8888    # 查看 8888 端口占用
lsof -i :8545    # 查看 8545 端口占用
```

**解决:**
```bash
# 方法 1: 停止占用端口的进程
kill <PID>

# 方法 2: 修改 docker-compose.yml 的端口映射
# 将 "8888:80" 改为 "9999:80"
# 将 "8545:8545" 改为 "9996:8545"
```

### Docker 镜像构建失败

**问题:** `docker-compose up` 报错

**排查:**
```bash
docker-compose build apache-proxy  # 单独构建 Apache 镜像
docker logs apache-rpc-proxy       # 查看错误日志
```

**常见原因:**
- 网络问题: Docker 镜像源配置错误
- 依赖问题: APT 源不可用（修改 Dockerfile 中的源）

### 请求返回 500 错误

**排查步骤:**
```bash
# 1. 查看 Apache 错误日志
docker logs apache-rpc-proxy --tail 50 | grep "\[error\]"

# 2. 检查 Lua 脚本语法
docker exec -it apache-rpc-proxy lua -e "dofile('/usr/local/apache2/scripts/rpc_proxy.lua')"

# 3. 检查配置文件
docker exec -it apache-rpc-proxy cat /etc/apache2/config/whitelist.json
```

### 修改配置后不生效

**问题:** 修改了 `whitelist.json` 但拦截规则未更新

**解决:** 必须重启 Apache 服务
```bash
docker-compose restart apache-proxy
# 或
./restart.sh
```

### 容器无法访问

**问题:** `curl: (7) Failed to connect`

**排查:**
```bash
# 1. 检查容器是否运行
docker-compose ps

# 2. 查看容器日志
docker logs apache-rpc-proxy

# 3. 进入容器内部测试
docker exec -it apache-rpc-proxy curl http://localhost:80/health
```

---

## 七、生产环境部署建议

### 1. 白名单配置

- 定期审核 `config/whitelist.json`
- 最小权限原则: 只添加必要的方法和地址
- 使用具体地址而非通配符

### 2. 日志管理

```bash
# 查看拦截统计
curl http://localhost:8545/stats | python3 -m json.tool

# 查看所有拦截记录
curl http://localhost:8545/blocked | python3 -m json.tool
```

### 3. 监控告警

建议监控指标:
- 容器运行状态
- HTTP 状态码分布（200 vs 403）
- Mock 服务的 `blocked_count` 增长

### 4. 安全加固

- 配置 HTTPS (修改 `rpc-proxy.conf`)
- 限制来源 IP（在 Apache 配置中添加 `Require ip`）
- 启用 HTTP 基础认证（如需）

---

## 八、版本更新

### 更新步骤

```bash
# 1. 拉取最新代码
git pull origin main

# 2. 重建镜像
docker-compose build apache-proxy

# 3. 重启服务
docker-compose up -d
```

### 版本说明

当前项目使用固定版本，确保环境一致性。如需升级版本，请修改相关文件:

- `apache/Dockerfile` - 基础镜像版本
- `docker-compose.yml` - 服务镜像版本
- `requirements.txt` (如存在) - Python 依赖版本

---

## 九、常见问题 FAQ

### Q1: 为什么使用 Lua 5.1 而不是最新版？

A: Apache `mod_lua` 模块目前仅支持 Lua 5.1 API，无法使用 Lua 5.2+ 的新特性。

### Q2: 如何添加新的白名单地址？

A: 编辑 `config/whitelist.json`，在 `allowed_addresses` 数组添加地址，然后重启 Apache 服务。

### Q3: Mock 服务和真实节点有什么区别？

A: Mock 服务仅返回模拟数据用于测试和演示，不连接真实区块链。生产环境应将 `http://rpc-backend:8545` 替换为真实的 Ethereum 节点地址。

### Q4: 如何将流量转发到真实节点？

A: 修改 `scripts/rpc_proxy.lua` 第 233 行的后端地址:
```lua
local cmd = string.format(
    "curl -s -X POST -H 'Content-Type: application/json' --data '%s' http://YOUR_REAL_NODE:8545/",
    escaped_body
)
```

### Q5: 日志存储在哪里？

A: Docker 容器日志默认存储在 Docker 引擎的日志驱动中。如需持久化，可在 `docker-compose.yml` 中配置 volume 挂载。

---

## 十、获取帮助

- 查看完整文档: `README.md`
- 运行测试套件: `./test/comprehensive_test.sh`
- 查看容器日志: `docker logs -f apache-rpc-proxy`
- GitHub Issues: https://github.com/JukLee0ira/Apache/issues

---

**部署完成!** 现在您可以开始使用 Ethereum RPC Filter 了。
