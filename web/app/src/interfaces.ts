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

export { IWorkerRecord, IWorkersState, IWorkerProps, ISignalRecord, ISignalsState, ISignalProps }
