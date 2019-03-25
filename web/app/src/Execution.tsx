import Button from '@material-ui/core/Button';
import Chip from '@material-ui/core/Chip';
import Modal from '@material-ui/core/Modal';
import Paper from '@material-ui/core/Paper';
import Snackbar from '@material-ui/core/Snackbar';
import TableRow from '@material-ui/core/TableRow';
import Typography from '@material-ui/core/Typography';
import classNames from 'classnames';
import { format, parse } from 'date-fns';
import * as React from 'react';
import SyntaxHighligher from 'react-syntax-highlighter';
import { dark } from 'react-syntax-highlighter/styles/hljs';

import { IExecutionProps, IGlobalWindow } from './interfaces';
import SchedulableRecordTableCell from './SchedulableRecordTableCell';

declare var window: IGlobalWindow

class Execution extends React.Component<IExecutionProps, any> {
  private statusChipColors: object = {
    completed: "primary",
    executing: "default",
    failed: "secondary",
  };

  constructor(props: IExecutionProps) {
    super(props)

    this.state = {
      detailModalOpen: false,
      notificationMessage: <span />,
      notificationOpen: false,
    }
  }

  public render() {
    const execution = this.props.execution;
    const rowClassNames = classNames({
      "failed": this.isFailed(),
    });

    return (
      <TableRow key={execution.id} className={rowClassNames} style={this.rowStyle()}>
        <SchedulableRecordTableCell><Chip label={execution.status} color={this.statusChipColors[execution.status]}/></SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{execution.id}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{execution.schedule_id}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{execution.schedule_type}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{execution.worker_id}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{this.formatTime(execution.executed_at)}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{this.formatTime(execution.completed_at)}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{execution.error_name}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>{execution.error_reason}</SchedulableRecordTableCell>
        <SchedulableRecordTableCell>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleDetailClick}>Detail</Button>

          <Modal
            aria-labelledby={`schedulable-record-modal-title-${execution.id}`}
            open={this.state.detailModalOpen}
            onClose={this.handleDetailModalClose}
            style={{display: "flex", alignItems: "center", justifyContent: "center"}}
          >
            <Paper className="execution-modal" style={{width: "600px", padding: "8px"}}>
              <Typography variant="title" id={`execution-modal-title-${execution.id}`}>
                Execution: {execution.id}
              </Typography>
              <SyntaxHighligher language="json" style={dark}>
                {JSON.stringify(execution, null, "  ")}
              </SyntaxHighligher>
            </Paper>
          </Modal>
        </SchedulableRecordTableCell>
        <SchedulableRecordTableCell>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleRetryClick}>Retry</Button>
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

  private isFailed(): boolean {
    return this.props.execution.status === "failed";
  }

  private rowStyle(): object {
    if (this.isFailed()) {
      return {backgroundColor: "#C62828"}
    } else {
      return {}
    }
  }

  private handleRetryClick = (event: any) => {
    const execution = this.props.execution;
    fetch(`${window.mountPath}/models/executions/${execution.id}/retry`, {
      headers: {"content-type": "application/json"},
      method: "POST"
    }).then(this.handleResponseStatus).then((res) => {
      this.setState({
        notificationMessage: <span>Retry id:{execution.id} schedule_type:{execution.schedule_type} schedule_id:{execution.schedule_id}</span>,
        notificationOpen: true,
      })
    }).catch((err) => {
      this.setState({
        notificationMessage: <span>Failed to retry ({err.message})</span>,
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

  private handleDetailClick = (ev: any) => {
    this.setState({
      ...this.state,
      detailModalOpen: true,
    })
  }

  private handleDetailModalClose = (ev: any) => {
    this.setState({
      ...this.state,
      detailModalOpen: false,
    })
  }
}

export default Execution;
