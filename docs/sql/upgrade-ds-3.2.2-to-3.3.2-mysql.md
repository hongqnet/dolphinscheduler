# DolphinScheduler 3.2.2 升级到 3.3.2 的 SQL-only 执行方案

本文档适用于生产环境不能执行 DolphinScheduler 自带升级工具
`tools/bin/upgrade-schema.sh`，只能由 DBA 或数据库平台执行 SQL 的场景。

目标版本：DolphinScheduler `3.3.2`

数据库类型：MySQL

## 结论

可以不执行 DS 的升级工具，直接按官方 SQL 文件顺序手工执行。

DS 升级工具本质上做了两件事：

1. 根据当前 `t_ds_version.version` 找到更高版本的 SQL 目录，按版本顺序执行 DDL/DML。
2. SQL 执行完成后，把 `t_ds_version.version` 更新为目标程序版本。

因此从 `3.2.2` 升级到 `3.3.2` 时，手工执行 SQL 的顺序必须是：

1. `3.3.0_schema/mysql/dolphinscheduler_ddl.sql`
2. `3.3.0_schema/mysql/dolphinscheduler_dml.sql`
3. `3.3.1_schema/mysql/dolphinscheduler_ddl.sql`
4. `3.3.1_schema/mysql/dolphinscheduler_dml.sql`
5. `3.3.2_schema/mysql/dolphinscheduler_ddl.sql`
6. `3.3.2_schema/mysql/dolphinscheduler_dml.sql`
7. 手工更新 `t_ds_version` 为 `3.3.2`

## 生产执行前置要求

执行 SQL 前必须满足以下条件：

1. 停止全部 DS 3.2.2 服务，包括 `master`、`worker`、`api`、`alert`。
2. 确认没有运行中的工作流实例。
3. 对 DS 元数据库做完整备份或快照。
4. 准备好 3.3.2 镜像和配置，但不要先启动 3.3.2 服务。
5. SQL 执行工具必须支持 MySQL `delimiter` 语法，因为 3.3.0 DDL 中包含存储过程。

如果当前数据库升级失败，不要继续启动 3.2.2 或 3.3.2 服务，应直接恢复备份，修正问题后重新升级。

## 执行前检查 SQL

检查当前数据库版本：

```sql
SELECT version FROM t_ds_version;
```

期望结果是：

```text
3.2.2
```

检查当前是否还是 3.2.x 的表结构：

```sql
SHOW TABLES LIKE 't_ds_process_definition';
SHOW TABLES LIKE 't_ds_workflow_definition';
```

期望结果：

- `t_ds_process_definition` 存在
- `t_ds_workflow_definition` 不存在

检查 3.3.2 新增唯一索引是否会失败。
3.3.2 会给调度表的工作流定义编码增加唯一索引，升级前字段名还是 `process_definition_code`：

```sql
SELECT process_definition_code, COUNT(*) AS c
FROM t_ds_schedules
GROUP BY process_definition_code
HAVING c > 1;
```

期望无结果。

如果有结果，说明同一个流程定义存在多条调度记录，执行到 3.3.2 DDL 时会失败，需要先确认哪些调度记录保留。

检查 3.3.0 不再兼容的任务类型：

```sql
SELECT task_type, COUNT(*) AS c
FROM t_ds_task_definition
WHERE task_type IN ('PIGEON', 'DYNAMIC')
GROUP BY task_type;

SELECT task_type, COUNT(*) AS c
FROM t_ds_task_definition_log
WHERE task_type IN ('PIGEON', 'DYNAMIC')
GROUP BY task_type;
```

期望无结果。

如果有结果，需要先改造或下线这些任务。

检查是否使用 Data Quality 相关功能。3.3.0 升级 SQL 会删除部分旧 DQ 表：

```sql
SHOW TABLES LIKE 't_ds_dq_%';
SHOW TABLES LIKE 't_ds_relation_rule_%';
```

如果生产仍依赖旧 DQ 数据，需要单独评估数据迁移和业务兼容性。

## SQL 执行顺序

以下路径是源码仓库中的官方 SQL 路径：

```text
dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.0_schema/mysql/dolphinscheduler_ddl.sql
dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.0_schema/mysql/dolphinscheduler_dml.sql
dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.1_schema/mysql/dolphinscheduler_ddl.sql
dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.1_schema/mysql/dolphinscheduler_dml.sql
dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.2_schema/mysql/dolphinscheduler_ddl.sql
dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.2_schema/mysql/dolphinscheduler_dml.sql
```

如果使用 MySQL CLI，可以按下面顺序执行：

```sql
SOURCE dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.0_schema/mysql/dolphinscheduler_ddl.sql;
SOURCE dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.0_schema/mysql/dolphinscheduler_dml.sql;
SOURCE dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.1_schema/mysql/dolphinscheduler_ddl.sql;
SOURCE dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.1_schema/mysql/dolphinscheduler_dml.sql;
SOURCE dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.2_schema/mysql/dolphinscheduler_ddl.sql;
SOURCE dolphinscheduler-dao/src/main/resources/sql/upgrade/3.3.2_schema/mysql/dolphinscheduler_dml.sql;
```

如果数据库平台不支持 `SOURCE`，就把这 6 个 SQL 文件内容按上述顺序合并成一个 SQL 工单执行。

注意：不要调整文件顺序。`3.3.0` 会把 `process` 命名体系升级为 `workflow` 命名体系，后续 `3.3.1`、`3.3.2` SQL 都依赖这个结构。

## 手工更新版本号

官方 SQL 文件本身不会更新 `t_ds_version`。

DS 的升级工具是在所有 SQL 执行完成后，由 Java 代码把版本号更新为当前程序版本。

手工执行 SQL 时，需要最后补充执行：

```sql
UPDATE t_ds_version
SET version = '3.3.2';
```

## 升级后验证 SQL

检查版本号：

```sql
SELECT version FROM t_ds_version;
```

期望结果：

```text
3.3.2
```

检查核心表是否已经切换到 3.3.x 命名：

```sql
SHOW TABLES LIKE 't_ds_workflow_definition';
SHOW TABLES LIKE 't_ds_process_definition';
```

期望结果：

- `t_ds_workflow_definition` 存在
- `t_ds_process_definition` 不存在

检查核心字段是否已经切换：

```sql
SHOW COLUMNS FROM t_ds_command LIKE 'workflow_definition_code';
SHOW COLUMNS FROM t_ds_command LIKE 'process_definition_code';
```

期望结果：

- `workflow_definition_code` 存在
- `process_definition_code` 不存在

检查 3.3.2 调度唯一索引：

```sql
SHOW INDEX FROM t_ds_schedules
WHERE Key_name = 'uniq_workflow_definition_code';
```

期望有结果。

检查子流程任务类型是否已转换：

```sql
SELECT task_type, COUNT(*) AS c
FROM t_ds_task_definition
WHERE task_type IN ('SUB_PROCESS', 'SUB_WORKFLOW')
GROUP BY task_type;
```

期望：

- `SUB_PROCESS` 为 0 或无结果
- `SUB_WORKFLOW` 可以有数据

## 服务启动顺序

数据库 SQL 升级验证通过后，再部署并启动 3.3.2 服务。

建议启动顺序：

1. `master`
2. `worker`
3. `api`
4. `alert`

启动后重点验证：

1. API 服务是否能正常登录。
2. 工作流定义列表是否能打开。
3. 调度列表是否正常。
4. 手工运行一个简单 SHELL 工作流。
5. Worker 日志是否能正常回传。
6. 告警服务是否能正常加载插件和发送测试告警。
7. Master/Worker 注册信息是否正常。

## 回滚原则

从 `3.2.2` 升级到 `3.3.2` 不是单纯改版本号，数据库表名和字段名发生了大规模变化。

如果 SQL 已经执行成功，不能只把镜像切回 `3.2.2`。

安全回滚方式只有：

1. 停止全部 DS 服务。
2. 恢复升级前数据库备份或快照。
3. 部署回 `3.2.2` 服务镜像和配置。
4. 启动并验证。

如果没有数据库备份，回滚风险很高，不建议在生产直接执行。
