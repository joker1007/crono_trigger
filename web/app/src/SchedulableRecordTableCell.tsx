import { createStyles, withStyles, WithStyles } from '@material-ui/core/styles';
import TableCell from '@material-ui/core/TableCell';
import * as React from 'react';

const styles = createStyles({
  property: {
    padding: "4px 16px 4px 8px"
  }
});

interface ITableCellProps extends WithStyles<typeof styles> {
  children: string | number | null | React.ReactNode | React.ReactNode[],
}

const SchedulableRecordTableCell = withStyles(styles)((props: ITableCellProps) => (
  <TableCell className={props.classes.property}>{props.children}</TableCell>
));

export default SchedulableRecordTableCell;
