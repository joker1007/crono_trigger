interface IGlobalWindow {
  mountPath: string
}

interface IWorkerRecord {
  worker_id: string,
  max_thread_size: number,
  current_queue_size: number,
  current_executing_size: number,
  polling_model_names: string[],
  executor_status: string,
  last_heartbeated_at: string,
}
interface IWorkersState {
  records: IWorkerRecord[]
}
interface IWorkerProps {
  worker: IWorkerRecord
}

interface ISignalRecord {
  worker_id: string,
  signal: string,
  sent_at: string,
  received_at: string,
}
interface ISignalsState {
  records: ISignalRecord[]
}
interface ISignalProps {
  signal: ISignalRecord
}

interface ISchedulableRecord {
  crono_trigger_status: string,
  id: number,
  cron: string | null,
  next_execute_at: string | null,
  last_executed_at: string | null,
  timezone: string | null,
  execute_lock: number,
  locked_by: string | null,
  started_at: string,
  finished_at: string,
  last_error_name: string,
  last_error_reason: string,
  last_error_time: string,
  retry_count: number,
  time_to_unlock: number,
  delay_sec: number,
}
interface ISchedulableRecordsProps {
  model_name: string
}
interface ISchedulableRecordsStates {
  records: ISchedulableRecord[]
}

interface ISchedulableRecordProps {
  model_name: string,
  record: ISchedulableRecord
}

export {
  IGlobalWindow,
  IWorkerRecord,
  IWorkersState,
  IWorkerProps,
  ISignalRecord,
  ISignalsState,
  ISignalProps,
  ISchedulableRecord,
  ISchedulableRecordsProps,
  ISchedulableRecordsStates,
  ISchedulableRecordProps
}
