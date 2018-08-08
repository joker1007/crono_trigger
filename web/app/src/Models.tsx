import Paper from '@material-ui/core/Paper';
import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableHead from '@material-ui/core/TableHead';
import TableRow from '@material-ui/core/TableRow';
import * as React from 'react';
import { Link } from "react-router-dom";

interface IModelsState {
  models: string[]
}

class Models extends React.Component<any, IModelsState> {
  constructor(props: any) {
    super(props)
    this.state = {models: []}
  }

  public componentDidMount() {
    this.fetchModels();
  }

  public fetchModels(): void {
    const that = this;
    fetch("./models.json")
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
              <TableCell>Model Name</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {this.state.models.map((model) => (
              <TableRow key={model}>
                <TableCell><Link to={`/models/${model}`}>{model}</Link></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Paper>
    )
  }
}

export default Models;
