import FormControl from '@material-ui/core/FormControl';
import Paper from '@material-ui/core/Paper';
import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableHead from '@material-ui/core/TableHead';
import TableRow from '@material-ui/core/TableRow';
import TextField from '@material-ui/core/TextField';
import { debounce } from 'lodash';
import * as React from 'react';

import { IGlobalWindow, ISchedulableRecordsProps, ISchedulableRecordsStates } from './interfaces';
import SchedulableRecord from './SchedulableRecord';

declare var window: IGlobalWindow;

class SchedulableRecords extends React.Component<ISchedulableRecordsProps, ISchedulableRecordsStates> {
  private fetchLoop: any;

  private handleTimeRangeFilterChange = debounce((event: any) => {
    this.setState({timeRangeMinute: parseInt(event.target.value, 10)});
    this.fetchSchedulableRecord();
  }, 500)

  constructor(props: ISchedulableRecordsProps) {
    super(props);

    this.state = {records: [], timeRangeMinute: 10};
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
    fetch(`${window.mountPath}/models/${this.props.model_name}.json?after=${this.state.timeRangeMinute}`)
      .then((res) => res.json())
      .then((data) => {
        that.setState(data);
      }).catch((err) => {
        console.error(err);
      });
  }

  public render() {
    return (
      <div id="schedulable-models">
        <FormControl className="filter-form">
          <TextField
            id="time-range-input"
            label="Time Range"
            type="number"
            defaultValue={this.state.timeRangeMinute}
            helperText="minute after"
            margin="normal"
            onChange={this.wrappedHandleTimeRangeFilterChange}
          />
        </FormControl>
        <Paper className="models-container" style={{marginTop: "8px"}}>
          <Table className="models">
            <TableHead>
              <TableRow>
                <TableCell>Status</TableCell>
                <TableCell>ID</TableCell>
                <TableCell>Cron</TableCell>
                <TableCell>Next Execute At</TableCell>
                <TableCell>Delay Sec</TableCell>
                <TableCell>Execute Lock</TableCell>
                <TableCell>Time To Unlock</TableCell>
                <TableCell>Last Executed At</TableCell>
                <TableCell>Timezone</TableCell>
                <TableCell>Locked By</TableCell>
                <TableCell>Last Error Name</TableCell>
                <TableCell>Last Error Reason</TableCell>
                <TableCell>Last Error Time</TableCell>
                <TableCell>Retry Count</TableCell>
                <TableCell>&nbsp;</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {this.state.records.map((record) => (
                <SchedulableRecord key={record.id} model_name={this.props.model_name} record={record} />
              ))}
            </TableBody>
          </Table>
        </Paper>
      </div>
    )
  }

  private wrappedHandleTimeRangeFilterChange = (event: any) => {
    event.persist();
    this.handleTimeRangeFilterChange(event);
  }
}

export default SchedulableRecords;
