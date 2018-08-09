import Button from '@material-ui/core/Button';
import Chip from '@material-ui/core/Chip';
import Snackbar from '@material-ui/core/Snackbar';
import TableCell from '@material-ui/core/TableCell';
import TableRow from '@material-ui/core/TableRow';
import classNames from 'classnames';
import * as React from 'react';

import { IGlobalWindow, ISchedulableRecordProps } from './interfaces';

declare var window: IGlobalWindow

class SchedulableRecord extends React.Component<ISchedulableRecordProps, any> {
  private statusChipColors: object = {
    locked: "secondary",
    not_scheduled: "default",
    waiting: "primary",
  };

  constructor(props: ISchedulableRecordProps) {
    super(props)

    this.state = {
      notificationMessage: <span />,
      notificationOpen: false,
    }
  }

  public render() {
    const record = this.props.record;
    const rowClassNames = classNames({
      "late": this.isLate(),
      "too-late": this.isTooLate(),
    });

    return (
      <TableRow key={record.id} className={rowClassNames} style={this.rowStyle()}>
        <TableCell><Chip label={record.crono_trigger_status} color={this.statusChipColors[record.crono_trigger_status]}/></TableCell>
        <TableCell>{record.id}</TableCell>
        <TableCell>{record.cron}</TableCell>
        <TableCell>{record.next_execute_at}</TableCell>
        <TableCell>{record.delay_sec}</TableCell>
        <TableCell>{record.execute_lock}</TableCell>
        <TableCell>{record.time_to_unlock}</TableCell>
        <TableCell>{record.last_executed_at}</TableCell>
        <TableCell>{record.timezone}</TableCell>
        <TableCell>{record.locked_by}</TableCell>
        <TableCell>{record.last_error_name}</TableCell>
        <TableCell>{record.last_error_reason}</TableCell>
        <TableCell>{record.last_error_time}</TableCell>
        <TableCell>{record.retry_count}</TableCell>
        <TableCell>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleUnlockClick}>Unlock</Button>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleRetryClick}>Retry</Button>
          <Button variant="contained" color="secondary" onClick={this.handleResetClick}>Reset</Button>

          <Snackbar
            anchorOrigin={{vertical: "bottom", horizontal: "right"}}
            open={this.state.notificationOpen}
            autoHideDuration={3000}
            onClose={this.handleNotificationClose}
            message={this.state.notificationMessage}
          />
        </TableCell>
      </TableRow>
    )
  }

  private isLate(): boolean {
    const record = this.props.record;
    return record.delay_sec > 60 && record.delay_sec <= 180;
  }

  private isTooLate(): boolean {
    const record = this.props.record;
    return record.delay_sec > 180;
  }

  private rowStyle(): object {
    if (this.isLate()) {
      return {backgroundColor: "#FFEA00"}
    } else if (this.isTooLate()) {
      return {backgroundColor: "#C62828"}
    } else {
      return {}
    }
  }

  private handleUnlockClick = (event: any) => {
    const record = this.props.record;
    fetch(`${window.mountPath}/models/${this.props.model_name}/${record.id}/unlock`, {
      headers: {"content-type": "application/json"},
      method: "POST"
    }).then(this.handleResponseStatus).then((res) => {
      this.setState({
        notificationMessage: <span>Unlock id:{record.id}</span>,
        notificationOpen: true,
      })
    }).catch((err) => {
      this.setState({
        notificationMessage: <span>Failed to unlock ({err.message})</span>,
        notificationOpen: true,
      })
    })
  }

  private handleRetryClick = (event: any) => {
    const record = this.props.record;
    fetch(`${window.mountPath}/models/${this.props.model_name}/${record.id}/retry`, {
      headers: {"content-type": "application/json"},
      method: "POST"
    }).then(this.handleResponseStatus).then((res) => {
      this.setState({
        notificationMessage: <span>Retry id:{record.id}</span>,
        notificationOpen: true,
      })
    }).catch((err) => {
      this.setState({
        notificationMessage: <span>Failed to retry ({err.message})</span>,
        notificationOpen: true,
      })
    })
  }

  private handleResetClick = (event: any) => {
    const record = this.props.record;
    fetch(`${window.mountPath}/models/${this.props.model_name}/${record.id}/reset`, {
      headers: {"content-type": "application/json"},
      method: "POST"
    }).then(this.handleResponseStatus).then((res) => {
      this.setState({
        notificationMessage: <span>Reset id:{record.id}</span>,
        notificationOpen: true,
      })
    }).catch((err) => {
      this.setState({
        notificationMessage: <span>Failed to reset ({err.message})</span>,
        notificationOpen: true,
      })
    })
  }

  private handleResponseStatus = (res: Response) => {
    if (!res.ok) {
      return res.json().then((data: any) => {
        throw new Error(data.error);
      })
    } else {
      return Promise.resolve(res);
    }
  }

  private handleNotificationClose = (ev: any, reason: any) => {
    this.setState({
      ...this.state,
      notificationOpen: false,
    })
  }
}

export default SchedulableRecord;
