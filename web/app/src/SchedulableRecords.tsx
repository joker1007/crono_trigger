import Chip from '@material-ui/core/Chip';
import Paper from '@material-ui/core/Paper';
import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableHead from '@material-ui/core/TableHead';
import TableRow from '@material-ui/core/TableRow';
import * as React from 'react';

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
}
interface ISchedulableRecordsProps {
  model_name: string
}
interface ISchedulableRecordsStates {
  records: ISchedulableRecord[]
}

class SchedulableRecords extends React.Component<ISchedulableRecordsProps, ISchedulableRecordsStates> {
  private fetchLoop: any;
  private statusChipColors: object = {
    locked: "secondary",
    not_scheduled: "default",
    waiting: "primary",
  };

  constructor(props: ISchedulableRecordsProps) {
    super(props)
    this.state = {records: []}
  }

  public componentDidMount() {
    this.fetchSchedulableRecord();
    this.setFetchSchedulableRecordLoop();
  }

  public componentWillUnmount() {
    if (this.fetchLoop) {
      clearTimeout(this.fetchLoop);
    }
  }

  public setFetchSchedulableRecordLoop(): void {
    this.fetchLoop = setTimeout(() => {
      this.fetchSchedulableRecord();
      this.setFetchSchedulableRecordLoop();
    }, 3000);
  }

  public fetchSchedulableRecord(): void {
    const that = this;
    fetch(`./${this.props.model_name}.json`)
      .then((res) => res.json())
      .then((data) => {
        that.setState(data);
      }).catch((err) => {
        console.error(err);
      });
  }

  public render() {
    return (
      <Paper className="models-container">
        <Table className="models">
          <TableHead>
            <TableRow>
              <TableCell>Status</TableCell>
              <TableCell>ID</TableCell>
              <TableCell>Cron</TableCell>
              <TableCell>Next Execute At</TableCell>
              <TableCell>Last Executed At</TableCell>
              <TableCell>Timezone</TableCell>
              <TableCell>Execute Lock</TableCell>
              <TableCell>Locked By</TableCell>
              <TableCell>Started At</TableCell>
              <TableCell>Finished At</TableCell>
              <TableCell>Last Error Name</TableCell>
              <TableCell>Last Error Reason</TableCell>
              <TableCell>Last Error Time</TableCell>
              <TableCell>Retry Count</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {this.state.records.map((record) => (
              <TableRow key={record.id}>
                <TableCell><Chip label={record.crono_trigger_status} color={this.statusChipColors[record.crono_trigger_status]}/></TableCell>
                <TableCell>{record.id}</TableCell>
                <TableCell>{record.cron}</TableCell>
                <TableCell>{record.next_execute_at}</TableCell>
                <TableCell>{record.last_executed_at}</TableCell>
                <TableCell>{record.timezone}</TableCell>
                <TableCell>{record.execute_lock}</TableCell>
                <TableCell>{record.locked_by}</TableCell>
                <TableCell>{record.started_at}</TableCell>
                <TableCell>{record.finished_at}</TableCell>
                <TableCell>{record.last_error_name}</TableCell>
                <TableCell>{record.last_error_reason}</TableCell>
                <TableCell>{record.last_error_time}</TableCell>
                <TableCell>{record.retry_count}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Paper>
    )
  }
}

export default SchedulableRecords;
