export function effectiveGrossPay(s: any): number { return s.fee_override != null && s.fee_override > 0 ? s.fee_override : Number(s.gross_pay); }
