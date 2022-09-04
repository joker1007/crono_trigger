import Paper from '@material-ui/core/Paper';
import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableHead from '@material-ui/core/TableHead';
import TableRow from '@material-ui/core/TableRow';
import * as React from 'react';

import { IGlobalWindow, IWorkersState } from "./interfaces";
import Worker from "./Worker";

declare var window: IGlobalWindow;

class Workers extends React.Component<any, IWorkersState> {
  private fetchLoop: ReturnType<typeof setTimeout>;

  constructor(props: any) {
    super(props);
    this.state = {records: []};
  }

  public componentDidMount() {
    this.fetchWorkers();
    this.setFetchWorkerLoop();
  }

  public componentWillUnmount() {
    if (this.fetchLoop) {
      clearTimeout(this.fetchLoop);
    }
  }

  public setFetchWorkerLoop(): void {
    this.fetchLoop = setTimeout(() => {
      this.fetchWorkers();
      this.setFetchWorkerLoop();
    }, 3000);
  }

  public fetchWorkers(): void {
    const that = this;
    fetch(`${window.mountPath}/workers.json`)
      .then((res) => res.json())
      .then((data) => {
        that.setState(data);
      }).catch((err) => {
        console.error(err);
      });
  }

  public render() {
    return (
      <Paper className="workers-container">
        <Table className="workers">
          <TableHead>
            <TableRow>
              <TableCell>Worker ID</TableCell>
              <TableCell numeric={true}>Thread</TableCell>
              <TableCell numeric={true}>Internal Queue</TableCell>
              <TableCell numeric={true}>Executing</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Polling Models</TableCell>
              <TableCell>Last Heatbeated At</TableCell>
              <TableCell>&nbsp;</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {this.state.records.map((record) => {
              return <Worker key={record.worker_id} worker={record} />
            })}
          </TableBody>
        </Table>
      </Paper>
    )
  }
}

export default Workers;
