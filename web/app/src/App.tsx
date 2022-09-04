import AppBar from '@material-ui/core/AppBar';
import IconButton from '@material-ui/core/IconButton';
import Menu from '@material-ui/core/Menu';
import MenuItem from '@material-ui/core/MenuItem';
import Toolbar from '@material-ui/core/Toolbar';
import Typography from '@material-ui/core/Typography';
import MenuIcon from '@material-ui/icons/Menu';
import * as React from 'react';
import { Link, Route, Switch } from "react-router-dom";
import './App.css';
import Models from './Models';
import SchedulableRecords from './SchedulableRecords';
import Signals from './Signals';
import Workers from './Workers';

interface IAppState {
  menuAnchorEl: HTMLElement | null
}

class App extends React.Component<any, IAppState> {
  private schedulableRecordsTitleRender: (props: any) => JSX.Element;
  private schedulableRecordsRender: (props: any) => JSX.Element;

  public constructor(props: any) {
    super(props);
    this.handleMenuButtonClick = this.handleMenuButtonClick.bind(this);
    this.handleMenuClose = this.handleMenuClose.bind(this);
    this.state = {menuAnchorEl: null};
    this.schedulableRecordsTitleRender = ({ match }) => (
      <Typography variant="title" color="inherit">{match.params.name}</Typography>
    )
    this.schedulableRecordsRender = ({ match }) => (
      <SchedulableRecords model_name={match.params.name} />
    )
  }

  public handleMenuButtonClick(event: any) {
    this.setState({menuAnchorEl: event.currentTarget});
  }

  public handleMenuClose() {
    this.setState({menuAnchorEl: null});
  }

  public render() {
    const { menuAnchorEl }= this.state;

    return (
      <div className="main">
        <AppBar position="static">
          <Toolbar>
            <IconButton className="menu" color="inherit" aria-label="Menu" onClick={this.handleMenuButtonClick}>
              <MenuIcon />
            </IconButton>
            <Menu id="nav-menu" anchorEl={menuAnchorEl} open={Boolean(menuAnchorEl)} onClose={this.handleMenuClose}>
              <MenuItem><Link to="/workers" onClick={this.handleMenuClose}>Workers</Link></MenuItem>
              <MenuItem><Link to="/signals" onClick={this.handleMenuClose}>Signals</Link></MenuItem>
              <MenuItem><Link to="/models" onClick={this.handleMenuClose}>Models</Link></MenuItem>
            </Menu>

            <Switch>
              <Route path="/workers">
                <Typography variant="title" color="inherit">Workers</Typography>
              </Route>
              <Route path="/signals">
                <Typography variant="title" color="inherit">Signals</Typography>
              </Route>
              <Route path="/models/:name" render={this.schedulableRecordsTitleRender} />
              <Route exact={true} path="/models">
                <Typography variant="title" color="inherit">Models</Typography>
              </Route>
            </Switch>
          </Toolbar>
        </AppBar>

        <div className="content" style={{"padding": "15px"}}>
          <Switch>
            <Route path="/workers">
              <Workers />
            </Route>
            <Route path="/signals">
              <Signals />
            </Route>
            <Route path="/models/:name" render={this.schedulableRecordsRender} />
            <Route exact={true} path="/models">
              <Models />
            </Route>
          </Switch>
        </div>
      </div>
    );
  }
}

export default App;
