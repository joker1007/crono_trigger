import Button from '@material-ui/core/Button';
import Chip from '@material-ui/core/Chip';
import Modal from '@material-ui/core/Modal';
import Snackbar from '@material-ui/core/Snackbar';
import TableRow from '@material-ui/core/TableRow';
import Typography from '@material-ui/core/Typography';
import classNames from 'classnames';
import { format, parse } from 'date-fns';
import * as React from 'react';

import { IGlobalWindow, ISchedulableRecordProps } from './interfaces';
import SchedulableRecordTableCell from './SchedulableRecordTableCell';

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
      detailModalOpen: false,
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
        <SchedulableRecordTableCell><Chip label={record.crono_trigger_status} color={this.statusChipColors[record.crono_trigger_status]}/></SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.id}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.cron}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{this.formatTime(record.next_execute_at)}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.delay_sec}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.execute_lock}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.time_to_unlock}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{this.formatTime(record.last_executed_at)}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.locked_by}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{this.formatTime(record.last_error_time)}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{record.retry_count}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleUnlockClick}>Unlock</Button>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleRetryClick}>Retry</Button>
          <Button variant="contained" color="secondary" onClick={this.handleResetClick}>Reset</Button>

          <Modal
            aria-labelledby={`schedulable-record-modal-title-${record.id}`}
            open={this.state.detailModalOpen}
            onClose={this.handleDetailModalClose}
          >
            <div className="schedulable-record-modal">
              <Typography variant="title" id={`schedulable-record-modal-title-${record.id}`}>
                {this.props.model_name}: {record.id}
              </Typography>
            </div>
          </Modal>

          <Snackbar
            anchorOrigin={{vertical: "bottom", horizontal: "right"}}
            open={this.state.notificationOpen}
            autoHideDuration={3000}
            onClose={this.handleNotificationClose}
            message={this.state.notificationMessage}
          />
        </SchedulableRecordTableCell>
      </TableRow>
    )
  }

  private formatTime(iso8601: string | null): string {
    if (iso8601 === null) {
      return "";
    }
    const date = parse(iso8601);
    return format(date, "YYYY/MM/DD (ddd) HH:mm:ss Z");
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

  private handleDetailModalClose = (ev: any) => {
    this.setState({
      ...this.state,
      detailModalOpen: false,
    })
  }
}

export default SchedulableRecord;
