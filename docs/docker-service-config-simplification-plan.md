# DolphinScheduler 3.2.2 Docker 服务配置精简方案

## 1. 背景与目标

当前仓库根目录 `Dockerfile` 会把 `apache-dolphinscheduler-3.2.2-bin.tar.gz`
解压到：

```text
/home/scrapyer/dolphinscheduler
```

然后同一个镜像分别运行 `alert`、`api`、`worker`、`master` 四类服务。之前每个
服务都依赖平台侧单独提供以下文件：

```text
liveness.sh
readiness.sh
dolphinscheduler_env.sh
application.yaml
common.properties
start.sh
```

本方案调整为：不依赖平台侧配置对象，不要求平台维护这些脚本和配置文件。所有启动脚本、
探活脚本和配置文件都在镜像构建阶段放入镜像，容器启动时只选择要启动的服务类型。

最终目标：

- 镜像内置 `entrypoint.sh` 统一选择并启动四类服务。
- 镜像内置 `liveness.sh`、`readiness.sh`，平台只负责调用，不维护脚本内容。
- 镜像内置 `dolphinscheduler_env.sh`、`application.yaml`、`common.properties`。
- 不再由平台侧覆盖 `start.sh`，直接使用 DolphinScheduler 发行包自带服务脚本。
- 每个服务只读取自身目录下的 `conf`，避免配置路径混乱。

如果你们仍然需要在不重建镜像的情况下调整配置，也不要回到“每个服务挂 6 个文件”的方式。
折中做法是每个容器最多挂载一个普通目录，例如
`/home/scrapyer/dolphinscheduler/runtime-conf`，再由镜像内置 `entrypoint.sh` 在启动前把
配置同步到当前服务自己的 `conf` 目录。

## 2. 3.2.2 启动脚本真实读取规则

DolphinScheduler 3.2.2 的 `master`、`worker`、`api`、`alert` 启动脚本逻辑一致：

```bash
BIN_DIR=$(dirname $0)
DOLPHINSCHEDULER_HOME=${DOLPHINSCHEDULER_HOME:-$(cd $BIN_DIR/..; pwd)}

source "$DOLPHINSCHEDULER_HOME/conf/dolphinscheduler_env.sh"

$JAVA_HOME/bin/java $JAVA_OPTS \
  -cp "$DOLPHINSCHEDULER_HOME/conf":"$DOLPHINSCHEDULER_HOME/libs/*" \
  ...
```

所以配置读取顺序的关键点是：

- `dolphinscheduler_env.sh` 从 `$DOLPHINSCHEDULER_HOME/conf` 读取。
- `application.yaml` 从 classpath 最前面的 `$DOLPHINSCHEDULER_HOME/conf` 读取。
- `common.properties` 也应放在 `$DOLPHINSCHEDULER_HOME/conf`。
- `DOLPHINSCHEDULER_HOME` 必须指向具体服务目录，不能指向发行包根目录。

结合当前 Dockerfile 的发行包解压目录，四个服务的正确配置目录如下：

| 服务 | 服务目录 | 配置目录 | 启动脚本 |
| --- | --- | --- | --- |
| master | `/home/scrapyer/dolphinscheduler/master-server` | `/home/scrapyer/dolphinscheduler/master-server/conf` | `master-server/bin/start.sh` |
| worker | `/home/scrapyer/dolphinscheduler/worker-server` | `/home/scrapyer/dolphinscheduler/worker-server/conf` | `worker-server/bin/start.sh` |
| api | `/home/scrapyer/dolphinscheduler/api-server` | `/home/scrapyer/dolphinscheduler/api-server/conf` | `api-server/bin/start.sh` |
| alert | `/home/scrapyer/dolphinscheduler/alert-server` | `/home/scrapyer/dolphinscheduler/alert-server/conf` | `alert-server/bin/start.sh` |

不要把 `DOLPHINSCHEDULER_HOME` 设置成：

```text
/home/scrapyer/dolphinscheduler
```

否则服务会去发行包根目录下找 `conf` 和 `libs`，这和 3.2.2 四服务目录结构不匹配。

## 3. 推荐目录结构

在仓库内增加一组 Docker 构建用配置文件，例如：

```text
deploy/docker/dolphinscheduler/
  bin/
    entrypoint.sh
    liveness.sh
    readiness.sh
  conf/
    common.properties
    dolphinscheduler_env.sh
    application/
      master/application.yaml
      worker/application.yaml
      api/application.yaml
      alert/application.yaml
```

镜像构建后，容器内形成：

```text
/home/scrapyer/dolphinscheduler/
  bin/
    entrypoint.sh
    liveness.sh
    readiness.sh
  master-server/
    bin/start.sh
    conf/application.yaml
    conf/common.properties
    conf/dolphinscheduler_env.sh
  worker-server/
    bin/start.sh
    conf/application.yaml
    conf/common.properties
    conf/dolphinscheduler_env.sh
  api-server/
    bin/start.sh
    conf/application.yaml
    conf/common.properties
    conf/dolphinscheduler_env.sh
  alert-server/
    bin/start.sh
    conf/application.yaml
    conf/common.properties
    conf/dolphinscheduler_env.sh
```

这样容器启动后只依赖镜像内部文件，不需要平台侧再提供上述脚本和配置。

## 4. 文件精简策略

| 文件 | 处理方式 | 说明 |
| --- | --- | --- |
| `start.sh` | 不自定义，不外部提供 | 使用发行包内置的 `*-server/bin/start.sh` |
| `entrypoint.sh` | 镜像内新增一个统一入口 | 根据服务类型选择对应服务目录 |
| `liveness.sh` | 镜像内置 | 检查对应 Java 进程是否存在 |
| `readiness.sh` | 镜像内置 | 检查对应服务端口或 actuator 是否可访问 |
| `dolphinscheduler_env.sh` | 镜像内置并复制到四个服务 `conf` | 放 Hadoop、Flink、DataX、Python 等运行环境变量 |
| `application.yaml` | 镜像内置并复制到各服务 `conf` | 每个服务保留自己的配置文件 |
| `common.properties` | 镜像内置并复制到四个服务 `conf` | 统一维护公共配置 |

## 5. 统一入口脚本

建议新增 `deploy/docker/dolphinscheduler/bin/entrypoint.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/home/scrapyer/dolphinscheduler"
SERVICE="${1:-${DS_SERVICE_TYPE:-}}"

case "${SERVICE}" in
  master)
    SERVICE_HOME="${BASE_DIR}/master-server"
    ;;
  worker)
    SERVICE_HOME="${BASE_DIR}/worker-server"
    ;;
  api)
    SERVICE_HOME="${BASE_DIR}/api-server"
    ;;
  alert)
    SERVICE_HOME="${BASE_DIR}/alert-server"
    ;;
  *)
    echo "Usage: entrypoint.sh {master|worker|api|alert}"
    echo "Or set DS_SERVICE_TYPE={master|worker|api|alert}"
    exit 2
    ;;
esac

for file in application.yaml common.properties dolphinscheduler_env.sh; do
  if [ ! -r "${SERVICE_HOME}/conf/${file}" ]; then
    echo "Missing config: ${SERVICE_HOME}/conf/${file}"
    exit 3
  fi
done

if [ -z "${JAVA_HOME:-}" ]; then
  echo "JAVA_HOME is empty"
  exit 4
fi

export DOCKER="${DOCKER:-true}"
export DOLPHINSCHEDULER_HOME="${SERVICE_HOME}"

echo "Starting DolphinScheduler ${SERVICE}"
echo "DOLPHINSCHEDULER_HOME=${DOLPHINSCHEDULER_HOME}"

exec "${SERVICE_HOME}/bin/start.sh"
```

关键点：

- `SERVICE` 可以来自第一个启动参数，也可以来自 `DS_SERVICE_TYPE`。
- 显式把 `DOLPHINSCHEDULER_HOME` 设置为具体服务目录。
- 启动前检查三类核心配置文件是否存在。
- 最后使用 `exec` 启动 Java 进程，保证容器主进程就是服务进程。

## 6. 镜像内置探活脚本

### 6.1 liveness.sh

`liveness.sh` 只判断服务进程是否还在：

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:-${DS_SERVICE_TYPE:-}}"

case "${SERVICE}" in
  master)
    CLASS_NAME="org.apache.dolphinscheduler.server.master.MasterServer"
    ;;
  worker)
    CLASS_NAME="org.apache.dolphinscheduler.server.worker.WorkerServer"
    ;;
  api)
    CLASS_NAME="org.apache.dolphinscheduler.api.ApiApplicationServer"
    ;;
  alert)
    CLASS_NAME="org.apache.dolphinscheduler.alert.AlertServer"
    ;;
  *)
    echo "Usage: liveness.sh {master|worker|api|alert}"
    exit 2
    ;;
esac

if ps -ef | grep -F "${CLASS_NAME}" | grep -v grep >/dev/null; then
  exit 0
fi

echo "DolphinScheduler ${SERVICE} process not found"
exit 1
```

### 6.2 readiness.sh

`readiness.sh` 判断服务端口是否已经就绪。为了不依赖 `curl`、`nc`、`wget`，可以使用
`bash` 的 `/dev/tcp`：

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:-${DS_SERVICE_TYPE:-}}"

case "${SERVICE}" in
  master)
    PORT="5679"
    PATH="/actuator/health/readiness"
    ;;
  worker)
    PORT="1235"
    PATH="/actuator/health/readiness"
    ;;
  api)
    PORT="12345"
    PATH="/dolphinscheduler/actuator/health/readiness"
    ;;
  alert)
    PORT="50053"
    PATH="/actuator/health/readiness"
    ;;
  *)
    echo "Usage: readiness.sh {master|worker|api|alert}"
    exit 2
    ;;
esac

exec 3<>"/dev/tcp/127.0.0.1/${PORT}" || {
  echo "DolphinScheduler ${SERVICE} port ${PORT} is not ready"
  exit 1
}

printf 'GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' "${PATH}" >&3
STATUS_LINE="$(timeout 3 head -n 1 <&3 || true)"

case "${STATUS_LINE}" in
  *" 200 "*)
    exit 0
    ;;
  *)
    echo "DolphinScheduler ${SERVICE} readiness failed: ${STATUS_LINE}"
    exit 1
    ;;
esac
```

如果线上基础镜像不稳定支持 `/dev/tcp`，就改为在 Dockerfile 中安装 `curl`，并把
`readiness.sh` 简化为：

```bash
curl -fsS "http://127.0.0.1:${PORT}${PATH}" >/dev/null
```

## 7. 配置文件落盘规则

### 7.1 common.properties

只维护一份公共配置源文件：

```text
deploy/docker/dolphinscheduler/conf/common.properties
```

构建镜像时复制到四个服务目录：

```text
master-server/conf/common.properties
worker-server/conf/common.properties
api-server/conf/common.properties
alert-server/conf/common.properties
```

生产环境重点确认：

- `resource.storage.type`
- `resource.storage.upload.base.path`
- `resource.hdfs.fs.defaultFS`
- `sudo.enable`
- `alert.rpc.port`
- `data-quality.jar.dir`
- `remote.logging.enable`
- `shell.env_source_list`
- `dolphin.scheduler.network.interface.restrict`

如果 `resource.storage.type=LOCAL`，多容器部署会有资源文件不一致风险。除非所有容器共享同
一个文件目录，否则建议使用 HDFS、S3、OSS 或其他共享存储。

### 7.2 dolphinscheduler_env.sh

只维护一份运行环境脚本：

```text
deploy/docker/dolphinscheduler/conf/dolphinscheduler_env.sh
```

构建镜像时复制到四个服务目录。建议只放任务运行依赖，不放数据库密码：

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export FLINK_HOME=/usr/local/flink-1.19
export DATAX_HOME=/usr/local/datax
export PATH=${JAVA_HOME}/bin:${FLINK_HOME}/bin:${DATAX_HOME}/bin:${PATH}
```

注意：DolphinScheduler 官方脚本会在任务执行时反复 source 这个文件。敏感配置放在这里
容易进入任务运行环境，不建议写入数据库密码、注册中心认证串等敏感信息。

### 7.3 application.yaml

每个服务维护自己的 `application.yaml`：

```text
deploy/docker/dolphinscheduler/conf/application/master/application.yaml
deploy/docker/dolphinscheduler/conf/application/worker/application.yaml
deploy/docker/dolphinscheduler/conf/application/api/application.yaml
deploy/docker/dolphinscheduler/conf/application/alert/application.yaml
```

构建镜像时分别覆盖到：

```text
master-server/conf/application.yaml
worker-server/conf/application.yaml
api-server/conf/application.yaml
alert-server/conf/application.yaml
```

四个服务都需要统一确认数据库和注册中心配置：

```yaml
spring:
  profiles:
    active: mysql
  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    url: jdbc:mysql://mysql-host:3306/dolphinscheduler?useUnicode=true&characterEncoding=UTF-8&useSSL=false&serverTimezone=Asia/Shanghai
    username: dolphinscheduler
    password: example-password

registry:
  type: zookeeper
  zookeeper:
    namespace: dolphinscheduler
    connect-string: zookeeper-host:2181
```

各服务端口保持 3.2.2 默认值：

| 服务 | RPC/业务端口 | 管理端口 |
| --- | ---: | ---: |
| master | `5678` | `5679` |
| worker | `1234` | `1235` |
| api | `12345` | `12345` |
| alert | `50052` | `50053` |

API 额外注意：

```yaml
server:
  servlet:
    context-path: /dolphinscheduler/
api:
  python-gateway:
    gateway-server-port: 25333
```

## 8. Dockerfile 改造建议

当前 Dockerfile 默认：

```dockerfile
workdir /home/scrapyer/dolphinscheduler
cmd ["bash", "start.sh"]
```

这不适合四服务拆分部署，因为发行包根目录并不是某个具体服务的 home。建议改为统一入口：

```dockerfile
ARG DEFAULT_SERVICE=master

ENV TZ=Asia/Shanghai
ENV DOCKER=true
ENV DS_SERVICE_TYPE=${DEFAULT_SERVICE}

WORKDIR /home/scrapyer/dolphinscheduler

COPY ./deploy/docker/dolphinscheduler/bin/entrypoint.sh ./bin/entrypoint.sh
COPY ./deploy/docker/dolphinscheduler/bin/liveness.sh ./bin/liveness.sh
COPY ./deploy/docker/dolphinscheduler/bin/readiness.sh ./bin/readiness.sh

COPY ./deploy/docker/dolphinscheduler/conf/common.properties /tmp/ds-conf/common.properties
COPY ./deploy/docker/dolphinscheduler/conf/dolphinscheduler_env.sh /tmp/ds-conf/dolphinscheduler_env.sh
COPY ./deploy/docker/dolphinscheduler/conf/application/master/application.yaml /tmp/ds-conf/master.application.yaml
COPY ./deploy/docker/dolphinscheduler/conf/application/worker/application.yaml /tmp/ds-conf/worker.application.yaml
COPY ./deploy/docker/dolphinscheduler/conf/application/api/application.yaml /tmp/ds-conf/api.application.yaml
COPY ./deploy/docker/dolphinscheduler/conf/application/alert/application.yaml /tmp/ds-conf/alert.application.yaml

RUN set -eux; \
    chmod +x ./bin/entrypoint.sh ./bin/liveness.sh ./bin/readiness.sh; \
    for svc in master worker api alert; do \
      cp /tmp/ds-conf/common.properties "${svc}-server/conf/common.properties"; \
      cp /tmp/ds-conf/dolphinscheduler_env.sh "${svc}-server/conf/dolphinscheduler_env.sh"; \
    done; \
    cp /tmp/ds-conf/master.application.yaml master-server/conf/application.yaml; \
    cp /tmp/ds-conf/worker.application.yaml worker-server/conf/application.yaml; \
    cp /tmp/ds-conf/api.application.yaml api-server/conf/application.yaml; \
    cp /tmp/ds-conf/alert.application.yaml alert-server/conf/application.yaml; \
    chown -R scrapyer:scrapyer /home/scrapyer/dolphinscheduler

USER scrapyer

ENTRYPOINT ["/home/scrapyer/dolphinscheduler/bin/entrypoint.sh"]
```

如果希望同一个镜像跑四个服务，启动容器时传第一个参数：

```bash
docker run --rm registry.example.com/dolphinscheduler:3.2.2-custom master
docker run --rm registry.example.com/dolphinscheduler:3.2.2-custom worker
docker run --rm registry.example.com/dolphinscheduler:3.2.2-custom api
docker run --rm registry.example.com/dolphinscheduler:3.2.2-custom alert
```

如果希望平台完全不传启动参数，可以基于同一 Dockerfile 构建四个镜像：

```bash
docker build --build-arg DEFAULT_SERVICE=master -t registry.example.com/ds-master:3.2.2 .
docker build --build-arg DEFAULT_SERVICE=worker -t registry.example.com/ds-worker:3.2.2 .
docker build --build-arg DEFAULT_SERVICE=api -t registry.example.com/ds-api:3.2.2 .
docker build --build-arg DEFAULT_SERVICE=alert -t registry.example.com/ds-alert:3.2.2 .
```

这种方式下，容器启动时不需要传服务类型，镜像自身已经决定默认服务。

## 9. 可选：只挂载一个普通配置目录

如果完全把配置打进镜像，会带来一个问题：改数据库、注册中心、资源中心配置时必须重新构建镜像。
如果你们不想依赖 K8s `ConfigMap`，但又希望配置能在运行时替换，可以只保留一个普通目录挂载。

### 9.1 目录结构

容器内固定目录：

```text
/home/scrapyer/dolphinscheduler/runtime-conf
```

目录内容：

```text
runtime-conf/
  common/
    common.properties
    dolphinscheduler_env.sh
  master/
    application.yaml
  worker/
    application.yaml
  api/
    application.yaml
  alert/
    application.yaml
```

规则：

- `common/common.properties` 是四个服务共用配置。
- `common/dolphinscheduler_env.sh` 是四个服务共用运行环境脚本。
- `master|worker|api|alert/application.yaml` 是服务级配置。
- 某个文件不存在时，继续使用镜像内置版本。

这样每个服务只需要一个目录挂载，而不是 6 个文件挂载。

### 9.2 entrypoint.sh 中增加配置同步

在 `entrypoint.sh` 中增加一个函数：

```bash
apply_runtime_conf() {
  local role="$1"
  local service_home="$2"
  local runtime_conf="${RUNTIME_CONF:-/home/scrapyer/dolphinscheduler/runtime-conf}"

  if [ ! -d "${runtime_conf}" ]; then
    return 0
  fi

  if [ -f "${runtime_conf}/common/common.properties" ]; then
    cp -f "${runtime_conf}/common/common.properties" \
      "${service_home}/conf/common.properties"
  fi

  if [ -f "${runtime_conf}/common/dolphinscheduler_env.sh" ]; then
    cp -f "${runtime_conf}/common/dolphinscheduler_env.sh" \
      "${service_home}/conf/dolphinscheduler_env.sh"
  fi

  if [ -f "${runtime_conf}/${role}/application.yaml" ]; then
    cp -f "${runtime_conf}/${role}/application.yaml" \
      "${service_home}/conf/application.yaml"
  fi
}
```

在启动前调用：

```bash
apply_runtime_conf "${SERVICE}" "${SERVICE_HOME}"
exec "${SERVICE_HOME}/bin/start.sh"
```

当前 Dockerfile 已经执行过：

```dockerfile
chown -R scrapyer:scrapyer /home/scrapyer/dolphinscheduler
```

因此以 `scrapyer` 用户启动时，可以把运行时目录中的文件复制到服务自己的 `conf` 目录。

### 9.3 该方式下的挂载清单

保留：

```text
/home/scrapyer/dolphinscheduler/runtime-conf
```

删除：

```text
start.sh
liveness.sh
readiness.sh
dolphinscheduler_env.sh
application.yaml
common.properties
```

注意这里的“删除”是指不再作为独立文件挂载；文件本身仍然存在于镜像内，或者存在于
`runtime-conf` 目录中。

## 10. 四服务启动和检查命令

### 10.1 启动

```bash
/home/scrapyer/dolphinscheduler/bin/entrypoint.sh master
/home/scrapyer/dolphinscheduler/bin/entrypoint.sh worker
/home/scrapyer/dolphinscheduler/bin/entrypoint.sh api
/home/scrapyer/dolphinscheduler/bin/entrypoint.sh alert
```

### 10.2 存活检查

```bash
/home/scrapyer/dolphinscheduler/bin/liveness.sh master
/home/scrapyer/dolphinscheduler/bin/liveness.sh worker
/home/scrapyer/dolphinscheduler/bin/liveness.sh api
/home/scrapyer/dolphinscheduler/bin/liveness.sh alert
```

### 10.3 就绪检查

```bash
/home/scrapyer/dolphinscheduler/bin/readiness.sh master
/home/scrapyer/dolphinscheduler/bin/readiness.sh worker
/home/scrapyer/dolphinscheduler/bin/readiness.sh api
/home/scrapyer/dolphinscheduler/bin/readiness.sh alert
```

## 11. 镜像构建前检查清单

构建镜像前确认：

- Dockerfile 有可用的基础镜像 `FROM`。
- `tz` 或 `TZ` 有默认值，避免时区命令失败。
- `JAVA_HOME` 和实际 JDK 路径一致。
- `entrypoint.sh`、`liveness.sh`、`readiness.sh` 都有执行权限。
- 四个服务目录下都有 `application.yaml`、`common.properties`、`dolphinscheduler_env.sh`。
- `worker-server/libs` 下有 `dolphinscheduler-data-quality-3.2.2.jar`。
- `/usr/local/flink-1.19` 和 `/usr/local/datax` 权限归属为 `scrapyer`。
- 数据库 schema 版本和服务版本一致，当前服务是 3.2.2 就应使用 3.2.2 兼容库表。

容器内可以用以下命令验证：

```bash
cd /home/scrapyer/dolphinscheduler

for svc in master worker api alert; do
  test -r "${svc}-server/conf/application.yaml"
  test -r "${svc}-server/conf/common.properties"
  test -r "${svc}-server/conf/dolphinscheduler_env.sh"
  test -x "${svc}-server/bin/start.sh"
done

test -x bin/entrypoint.sh
test -x bin/liveness.sh
test -x bin/readiness.sh
```

## 12. 推荐落地步骤

1. 在仓库中新增 `deploy/docker/dolphinscheduler/` 目录，提交入口脚本、探活脚本和配置源文件。
2. 调整 Dockerfile，把配置源文件复制到四个服务自己的 `conf` 目录。
3. 把 Dockerfile 默认 `cmd ["bash", "start.sh"]` 改为统一 `ENTRYPOINT`。
4. 先构建一个测试镜像，用 `docker run ... master` 验证 master 能启动。
5. 再分别验证 `worker`、`api`、`alert`。
6. 如果配置可以固化进镜像，直接删除平台侧原来维护的脚本和配置挂载。
7. 如果配置必须运行时替换，只保留一个 `runtime-conf` 目录挂载。
8. 如果平台需要探活，只调用镜像内的：

```text
/home/scrapyer/dolphinscheduler/bin/liveness.sh <service>
/home/scrapyer/dolphinscheduler/bin/readiness.sh <service>
```

## 13. 风险与边界

- 如果把数据库密码写入 `application.yaml` 并打进镜像，镜像仓库会保存敏感信息；更安全的方式是构建环境专用镜像，或者启动时从安全文件读取后再渲染配置。
- 如果所有环境共用一个镜像，但数据库地址不同，就不能完全把配置固化进镜像，需要保留启动时渲染配置的能力。
- 如果平台不传服务类型，建议构建四个服务镜像；如果平台可以传一个参数，建议一个镜像复用四个服务。
- 3.2.2 的四服务脚本要求 `DOLPHINSCHEDULER_HOME` 指向服务目录，升级到 3.3.x/3.4.x 后需要重新确认启动脚本逻辑。
- `resource.storage.type=LOCAL` 不适合多容器共享资源，除非容器共享同一个资源目录。
- 使用 `runtime-conf` 目录时，不要把整个服务 `conf` 目录挂进去，只挂统一目录并由入口脚本复制指定文件。

## 14. 最终推荐

推荐采用：

```text
一个基础 Dockerfile
+ 一套镜像内置配置源文件
+ 一个 entrypoint.sh
+ 一个 liveness.sh
+ 一个 readiness.sh
+ 四个服务通过参数或 DEFAULT_SERVICE 区分
```

如果平台侧想最简：

```text
构建四个镜像：
  ds-master:3.2.2
  ds-worker:3.2.2
  ds-api:3.2.2
  ds-alert:3.2.2

每个镜像只设置不同的 DEFAULT_SERVICE。
平台只启动镜像，不再维护 DS 的脚本和配置文件。
```

如果镜像数量想最少：

```text
构建一个镜像：
  dolphinscheduler:3.2.2-custom

启动时传入：
  master / worker / api / alert
```

如果配置想保留运行时替换能力：

```text
每个服务只挂载一个目录：
  /home/scrapyer/dolphinscheduler/runtime-conf

不再单独挂载：
  start.sh
  liveness.sh
  readiness.sh
  dolphinscheduler_env.sh
  application.yaml
  common.properties
```
