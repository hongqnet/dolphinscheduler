/*
 * Roll back a MySQL schema that was upgraded from DolphinScheduler 3.2.2
 * to 3.3.1 so it can be used again by DolphinScheduler 3.2.2 services.
 *
 * Run only after stopping all DS services and taking a fresh database backup.
 * This script targets the normal upgrade path: 3.2.2 -> 3.3.0 -> 3.3.1.
 *
 * Important data note:
 * 3.3.0 dropped legacy listener/trigger/DQ tables. This script restores
 * compatible table structure, but deleted rows can only be restored from the
 * pre-upgrade backup.
 */

SET FOREIGN_KEY_CHECKS = 0;

SELECT version AS current_schema_version FROM t_ds_version;
SHOW TABLES LIKE 't_ds_workflow_definition';
SHOW TABLES LIKE 't_ds_process_definition';

-- Reverse 3.3.0 DML while the 3.3 table/column names still exist.
UPDATE t_ds_task_definition
SET task_params = REPLACE(task_params, 'workflowDefinitionCode', 'processDefinitionCode')
WHERE task_type = 'SUB_WORKFLOW';

UPDATE t_ds_task_definition_log
SET task_params = REPLACE(task_params, 'workflowDefinitionCode', 'processDefinitionCode')
WHERE task_type = 'SUB_WORKFLOW';

UPDATE t_ds_task_definition
SET task_type = 'SUB_PROCESS'
WHERE task_type = 'SUB_WORKFLOW';

UPDATE t_ds_task_definition_log
SET task_type = 'SUB_PROCESS'
WHERE task_type = 'SUB_WORKFLOW';

-- Reverse 3.3.1 DDL.
ALTER TABLE t_ds_command
  ADD COLUMN test_flag tinyint(4) DEFAULT NULL COMMENT 'test flag: 0 normal, 1 test run';

ALTER TABLE t_ds_error_command
  ADD COLUMN test_flag tinyint(4) DEFAULT NULL COMMENT 'test flag: 0 normal, 1 test run';

ALTER TABLE t_ds_workflow_instance
  ADD COLUMN test_flag tinyint(4) DEFAULT NULL COMMENT 'test flag: 0 normal, 1 test run';

ALTER TABLE t_ds_task_instance
  ADD COLUMN test_flag tinyint(4) DEFAULT NULL COMMENT 'test flag: 0 normal, 1 test run';

ALTER TABLE t_ds_workflow_definition
  DROP INDEX uniq_workflow_definition_code;

ALTER TABLE t_ds_workflow_definition
  MODIFY id int(11) NOT NULL COMMENT 'self-increasing id';

ALTER TABLE t_ds_workflow_definition
  DROP PRIMARY KEY;

ALTER TABLE t_ds_workflow_definition
  ADD PRIMARY KEY (id, code);

ALTER TABLE t_ds_workflow_definition
  MODIFY id int(11) NOT NULL AUTO_INCREMENT COMMENT 'self-increasing id';

-- Reverse 3.3.0 process -> workflow renames.
ALTER TABLE t_ds_alert
  CHANGE workflow_definition_code process_definition_code bigint(20) NULL COMMENT 'process_definition_code',
  CHANGE workflow_instance_id process_instance_id int(11) NULL COMMENT 'process_instance_id',
  MODIFY warning_type tinyint(4) DEFAULT '2' COMMENT '1 process is successfully, 2 process/task is failed';

ALTER TABLE t_ds_command
  CHANGE workflow_definition_code process_definition_code bigint(20) NOT NULL COMMENT 'process definition code',
  CHANGE workflow_definition_version process_definition_version int(11) NULL DEFAULT 0 COMMENT 'process definition version',
  CHANGE workflow_instance_id process_instance_id int(11) NULL DEFAULT 0 COMMENT 'process instance id',
  CHANGE workflow_instance_priority process_instance_priority int(11) NULL DEFAULT 2 COMMENT 'process instance priority: 0 Highest, 1 High, 2 Medium, 3 Low, 4 Lowest',
  MODIFY command_type tinyint(4) NULL COMMENT 'Command type: 0 start process, 1 start execution from current node, 2 resume fault-tolerant process, 3 resume pause process, 4 start execution from failed node, 5 complement, 6 schedule, 7 rerun, 8 pause, 9 stop, 10 resume waiting thread',
  MODIFY warning_type tinyint(4) NULL DEFAULT 0 COMMENT 'Alarm type: 0 is not sent, 1 process is sent successfully, 2 process is sent failed, 3 process is sent successfully and all failures are sent';

ALTER TABLE t_ds_error_command
  CHANGE workflow_definition_code process_definition_code bigint(20) NOT NULL COMMENT 'process definition code',
  CHANGE workflow_definition_version process_definition_version int(11) NULL DEFAULT 0 COMMENT 'process definition version',
  CHANGE workflow_instance_id process_instance_id int(11) NULL DEFAULT 0 COMMENT 'process instance id: 0',
  CHANGE workflow_instance_priority process_instance_priority int(11) NULL DEFAULT 2 COMMENT 'process instance priority, 0 Highest, 1 High, 2 Medium, 3 Low, 4 Lowest';

ALTER TABLE t_ds_workflow_task_relation
  CHANGE workflow_definition_code process_definition_code bigint(20) NOT NULL COMMENT 'process code',
  CHANGE workflow_definition_version process_definition_version int(11) NOT NULL COMMENT 'process version';

ALTER TABLE t_ds_workflow_task_relation_log
  CHANGE workflow_definition_code process_definition_code bigint(20) NOT NULL COMMENT 'process code',
  CHANGE workflow_definition_version process_definition_version int(11) NOT NULL COMMENT 'process version',
  RENAME INDEX idx_workflow_code_version TO idx_process_code_version;

ALTER TABLE t_ds_workflow_instance
  CHANGE workflow_definition_code process_definition_code bigint(20) NOT NULL COMMENT 'process definition code',
  CHANGE workflow_definition_version process_definition_version int(11) NOT NULL DEFAULT 1 COMMENT 'process definition version',
  CHANGE is_sub_workflow is_sub_process int(11) NULL DEFAULT 0 COMMENT 'flag, whether the process is sub process',
  CHANGE workflow_instance_priority process_instance_priority int(11) NULL DEFAULT 2 COMMENT 'process instance priority. 0 Highest, 1 High, 2 Medium, 3 Low, 4 Lowest',
  CHANGE next_workflow_instance_id next_process_instance_id int(11) NULL DEFAULT 0 COMMENT 'serial queue next processInstanceId',
  MODIFY name varchar(255) NULL COMMENT 'process instance name',
  MODIFY state tinyint(4) NULL COMMENT 'process instance Status: 0 commit succeeded, 1 running, 2 prepare to pause, 3 pause, 4 prepare to stop, 5 stop, 6 fail, 7 succeed, 8 need fault tolerance, 9 kill, 10 wait for thread, 11 wait for dependency to complete',
  MODIFY recovery tinyint(4) NULL COMMENT 'process instance failover flag: 0 normal, 1 failover instance',
  MODIFY start_time datetime NULL COMMENT 'process instance start time',
  MODIFY end_time datetime NULL COMMENT 'process instance end time',
  MODIFY run_times int(11) NULL COMMENT 'process instance run times',
  MODIFY host varchar(135) NULL COMMENT 'process instance host',
  MODIFY failure_strategy tinyint(4) NULL DEFAULT 0 COMMENT 'failure strategy. 0 end the process when node failed, 1 continue running the other nodes when node failed',
  MODIFY warning_type tinyint(4) NULL DEFAULT 0 COMMENT 'warning type. 0 no warning, 1 warning if process success, 2 warning if process failed, 3 warning if success',
  MODIFY history_cmd text NULL COMMENT 'history commands of process instance operation',
  MODIFY restart_time datetime NULL COMMENT 'process instance restart time',
  RENAME INDEX workflow_instance_index TO process_instance_index;

ALTER TABLE t_ds_schedules
  CHANGE workflow_definition_code process_definition_code bigint(20) NOT NULL COMMENT 'process definition code',
  CHANGE workflow_instance_priority process_instance_priority int(11) NULL DEFAULT 2 COMMENT 'process instance priority: 0 Highest, 1 High, 2 Medium, 3 Low, 4 Lowest',
  MODIFY warning_type tinyint(4) NOT NULL COMMENT 'Alarm type: 0 is not sent, 1 process is sent successfully, 2 process is sent failed, 3 process is sent successfully and all failures are sent';

ALTER TABLE t_ds_task_instance
  CHANGE workflow_instance_id process_instance_id int(11) NULL COMMENT 'process instance id',
  CHANGE workflow_instance_name process_instance_name varchar(255) NULL COMMENT 'process instance name',
  RENAME INDEX workflow_instance_id TO process_instance_id;

ALTER TABLE t_ds_task_group_queue
  CHANGE workflow_instance_id process_id int(11) NULL COMMENT 'process instance id';

ALTER TABLE t_ds_relation_workflow_instance
  CHANGE parent_workflow_instance_id parent_process_instance_id int(11) NULL COMMENT 'parent process instance id',
  CHANGE workflow_instance_id process_instance_id int(11) NULL COMMENT 'child process instance id',
  MODIFY parent_task_instance_id int(11) NULL COMMENT 'parent task instance id',
  DROP INDEX idx_parent_workflow_task,
  DROP INDEX idx_workflow_instance_id,
  ADD INDEX idx_parent_process_task (parent_process_instance_id, parent_task_instance_id),
  ADD INDEX idx_process_instance_id (process_instance_id);

RENAME TABLE t_ds_workflow_definition TO t_ds_process_definition;
RENAME TABLE t_ds_workflow_definition_log TO t_ds_process_definition_log;
RENAME TABLE t_ds_workflow_task_relation TO t_ds_process_task_relation;
RENAME TABLE t_ds_workflow_task_relation_log TO t_ds_process_task_relation_log;
RENAME TABLE t_ds_workflow_instance TO t_ds_process_instance;
RENAME TABLE t_ds_relation_workflow_instance TO t_ds_relation_process_instance;

ALTER TABLE t_ds_process_definition
  DROP INDEX idx_project_code,
  RENAME INDEX workflow_unique TO process_unique,
  MODIFY name varchar(255) NULL COMMENT 'process definition name',
  MODIFY version int(11) NOT NULL DEFAULT 1 COMMENT 'process definition version',
  MODIFY release_state tinyint(4) NULL COMMENT 'process definition release state: 0 offline, 1 online',
  MODIFY user_id int(11) NULL COMMENT 'process definition creator id';

ALTER TABLE t_ds_process_definition_log
  DROP INDEX idx_project_code,
  MODIFY name varchar(255) NULL COMMENT 'process definition name',
  MODIFY version int(11) NOT NULL DEFAULT 1 COMMENT 'process definition version',
  MODIFY release_state tinyint(4) NULL COMMENT 'process definition release state: 0 offline, 1 online',
  MODIFY user_id int(11) NULL COMMENT 'process definition creator id';

-- Restore columns dropped by 3.3.0.
ALTER TABLE t_ds_alert_plugin_instance
  ADD COLUMN instance_type int NOT NULL DEFAULT '0',
  ADD COLUMN warning_type int NOT NULL DEFAULT '3';

ALTER TABLE t_ds_worker_group
  ADD COLUMN other_params_json text NULL DEFAULT NULL COMMENT 'other params json';

ALTER TABLE t_ds_task_definition
  ADD COLUMN is_cache tinyint(2) DEFAULT '0' COMMENT '0 not available, 1 available' AFTER flag,
  DROP INDEX idx_project_code;

ALTER TABLE t_ds_task_definition_log
  ADD COLUMN is_cache tinyint(2) DEFAULT '0' COMMENT '0 not available, 1 available' AFTER flag;

ALTER TABLE t_ds_task_instance
  ADD COLUMN is_cache tinyint(2) DEFAULT '0' COMMENT '0 not available, 1 available' AFTER flag,
  ADD COLUMN cache_key varchar(200) DEFAULT NULL COMMENT 'cache_key' AFTER is_cache,
  ADD INDEX idx_cache_key (cache_key) USING BTREE;

-- Remove 3.3-only tables.
DROP TABLE IF EXISTS t_ds_task_instance_context;
DROP TABLE IF EXISTS t_ds_workflow_task_lineage;
DROP TABLE IF EXISTS t_ds_jdbc_registry_data_change_event;
DROP TABLE IF EXISTS t_ds_jdbc_registry_client_heartbeat;
DROP TABLE IF EXISTS t_ds_jdbc_registry_lock;
DROP TABLE IF EXISTS t_ds_jdbc_registry_data;

-- Recreate legacy tables that 3.3.0 dropped. Rows must come from backup if needed.
CREATE TABLE IF NOT EXISTS t_ds_trigger_relation (
  id bigint(20) NOT NULL AUTO_INCREMENT,
  trigger_type int(11) NOT NULL DEFAULT '0' COMMENT '0 process 1 task',
  trigger_code bigint(20) NOT NULL,
  job_id bigint(20) NOT NULL,
  create_time datetime DEFAULT NULL,
  update_time datetime DEFAULT NULL,
  PRIMARY KEY (id),
  KEY t_ds_trigger_relation_trigger_code_IDX (trigger_code),
  UNIQUE KEY t_ds_trigger_relation_UN (trigger_type, job_id, trigger_code)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

CREATE TABLE IF NOT EXISTS t_ds_listener_event (
  id int(11) NOT NULL AUTO_INCREMENT COMMENT 'key',
  content text COMMENT 'listener event json content',
  sign char(64) NOT NULL DEFAULT '' COMMENT 'sign=sha1(content)',
  post_status tinyint(4) NOT NULL DEFAULT '0' COMMENT '0 wait running, 1 success, 2 failed, 3 partial success',
  event_type int(11) NOT NULL COMMENT 'listener event type',
  log text COMMENT 'log',
  create_time datetime DEFAULT NULL COMMENT 'create time',
  update_time datetime DEFAULT NULL COMMENT 'update time',
  PRIMARY KEY (id),
  KEY idx_status (post_status) USING BTREE,
  KEY idx_sign (sign) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

-- Keep 3.2.2 schema changes. The 3.2.2 service expects:
--   t_ds_relation_project_worker_group
--   t_ds_project_parameter.operator
--   t_ds_project_parameter.param_data_type
--   t_ds_audit_log model_id/model_name/model_type/operation_type/create_time layout
-- Do not reverse those structures when rolling back to 3.2.2.

/*
 * If your 3.2.2 deployment uses Data Quality, restore these dropped tables
 * and their rows from the pre-upgrade backup or from the 3.2.2 init DDL:
 *   t_ds_dq_comparison_type
 *   t_ds_dq_rule_execute_sql
 *   t_ds_dq_rule_input_entry
 *   t_ds_dq_task_statistics_value
 *   t_ds_dq_execute_result
 *   t_ds_dq_rule
 *   t_ds_relation_rule_input_entry
 *   t_ds_relation_rule_execute_sql
 */

UPDATE t_ds_version
SET version = '3.2.2';

SET FOREIGN_KEY_CHECKS = 1;

SELECT version AS rolled_back_schema_version FROM t_ds_version;
SHOW TABLES LIKE 't_ds_process_definition';
SHOW COLUMNS FROM t_ds_process_definition LIKE 'code';
