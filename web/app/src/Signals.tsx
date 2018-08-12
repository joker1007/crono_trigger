import Paper from '@material-ui/core/Paper';
import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableHead from '@material-ui/core/TableHead';
import TableRow from '@material-ui/core/TableRow';
import * as React from 'react';

import { IGlobalWindow, ISignalsState } from './interfaces';
import Signal from './Signal';

declare var window: IGlobalWindow;

class Signals extends React.Component<any, ISignalsState> {
  private fetchLoop: any;

  constructor(props: any) {
    super(props)
    this.state = {records: []}
  }

  public componentDidMount() {
    this.fetchSignals();
    this.setFetchSignalLoop();
  }

  public componentWillUnmount() {
    if (this.fetchLoop) {
      clearTimeout(this.fetchLoop);
    }
  }

  public setFetchSignalLoop(): void {
    this.fetchLoop = setTimeout(() => {
      this.fetchSignals();
      this.setFetchSignalLoop();
    }, 3000);
  }

  public fetchSignals(): void {
    const that = this;
    fetch(`${window.mountPath}/signals.json`)
      .then((res) => res.json())
      .then((data) => {
        that.setState(data);
      }).catch((err) => {
        console.error(err);
      });
  }

  public render() {
    return (
      <Paper className="signals-container">
        <Table className="signals">
          <TableHead>
            <TableRow>
              <TableCell>Worker ID</TableCell>
              <TableCell>Signal</TableCell>
              <TableCell>Sent At</TableCell>
              <TableCell>Received At</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {this.state.records.map((record) => {
              return <Signal key={`${record.worker_id}-${record.sent_at}`} signal={record} />
            })}
          </TableBody>
        </Table>
      </Paper>
    )
  }
}

export default Signals;
