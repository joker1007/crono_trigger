import Button from '@material-ui/core/Button';
import Snackbar from '@material-ui/core/Snackbar';
import TableCell from '@material-ui/core/TableCell';
import TableRow from '@material-ui/core/TableRow';
import * as React from 'react';

import { IWorkerProps } from "./interfaces";

class Worker extends React.Component<IWorkerProps, any> {
  constructor(props: IWorkerProps) {
    super(props)
    this.handleQuietClick = this.handleQuietClick.bind(this)
    this.handleStopClick = this.handleStopClick.bind(this)
    this.handleNotificationClose = this.handleNotificationClose.bind(this)
    this.state = {
      notificationMessage: <span />,
      notificationOpen: false,
    }
  }

  public render() {
    const worker = this.props.worker;
    return (
      <TableRow>
        <TableCell>{worker.worker_id}</TableCell>
        <TableCell numeric={true}>{worker.max_thread_size}</TableCell>
        <TableCell numeric={true}>{worker.current_queue_size}</TableCell>
        <TableCell numeric={true}>{worker.current_executing_size}</TableCell>
        <TableCell>{worker.executor_status}</TableCell>
        <TableCell>{worker.polling_model_names}</TableCell>
        <TableCell>{worker.last_heartbeated_at}</TableCell>
        <TableCell>
          <Button variant="contained" style={{"marginRight": "8px"}} onClick={this.handleQuietClick}>Quiet</Button>
          <Button variant="contained" color="secondary" onClick={this.handleStopClick}>Stop</Button>
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

  private handleQuietClick(event: any) {
    const worker = this.props.worker;
    fetch("./signals", {
      body: JSON.stringify({"worker_id": worker.worker_id, "signal": "TSTP"}),
      headers: {"content-type": "application/json"},
      method: "POST"
    }).then(this.handleResponseStatus).then((res) => {
      this.setState({
        notificationMessage: <span>Quiet {worker.worker_id}</span>,
        notificationOpen: true,
      })
    }).catch((err) => {
      this.setState({
        notificationMessage: <span>Failed to Quiet ({err.message})</span>,
        notificationOpen: true,
      })
    })
  }

  private handleStopClick(event: any) {
    const worker = this.props.worker;
    fetch("./signals", {
      body: JSON.stringify({"worker_id": worker.worker_id, "signal": "TERM"}),
      headers: {"content-type": "application/json"},
      method: "POST"
    }).then(this.handleResponseStatus).then((res) => {
      this.setState({
        notificationMessage: <span>Stop {worker.worker_id}</span>,
        notificationOpen: true,
      })
    }).catch((err) => {
      this.setState({
        notificationMessage: <span>Failed to Stop ({err.message})</span>,
        notificationOpen: true,
      })
    })
  }

  private handleResponseStatus(res: Response): Promise<Response | Error> {
    if (!res.ok) {
      return res.json().then((data: any) => {
        throw new Error(data.error);
      })
    } else {
      return Promise.resolve(res);
    }
  }

  private handleNotificationClose(ev: any, reason: any) {
    this.setState({
      ...this.state,
      notificationOpen: false,
    })
  }
}

export default Worker;
