import TableCell from '@material-ui/core/TableCell';
import TableRow from '@material-ui/core/TableRow';
import * as React from 'react';

import { ISignalProps } from './interfaces';

class Signal extends React.Component<ISignalProps, any> {
  public render() {
    const signal = this.props.signal;
    return (
      <TableRow>
        <TableCell>{signal.worker_id}</TableCell>
        <TableCell>{signal.signal}</TableCell>
        <TableCell>{signal.sent_at}</TableCell>
        <TableCell>{signal.received_at}</TableCell>
      </TableRow>
    )
  }
}

export default Signal;
