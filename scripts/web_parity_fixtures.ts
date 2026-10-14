import { calculateShiftPay, DEFAULT_RATES } from '@/lib/shiftCalculator';
import { groupShiftsForInvoice } from '@/lib/invoiceGrouping';
const store: Record<string,string> = {};
(globalThis as any).window = {};
(globalThis as any).localStorage = { getItem: (k: string) => store[k] ?? null, setItem: (k: string, v: string) => { store[k] = v; } };
const custom = { ...DEFAULT_RATES, rate_weekday: 65.47, rate_evening: 72.08, rate_saturday: 92.12, rate_sunday: 118.77 };
const cases: any[] = [
 ['2026-10-14','09:00','17:00',false,false,false],   // Wed day
 ['2026-10-14','15:00','21:00',false,false,false],   // Wed into evening
 ['2026-10-14','20:00','02:00',false,false,false],   // Wed→Thu crosses midnight
 ['2026-10-16','20:00','02:00',false,false,false],   // Fri→Sat
 ['2026-10-17','10:00','20:00',false,false,false],   // Sat incl evening hours (no evening rate)
 ['2026-10-18','22:00','08:00',false,false,false],   // Sun→Mon overnight
 ['2026-10-14','09:00','17:00',false,true,false],    // PH
 ['2026-10-14','09:00','17:00',false,false,true],    // OT
 ['2026-10-14','22:00','06:00',true,false,false],    // weekday sleepover
 ['2026-10-17','22:00','06:00',true,false,false],    // Sat sleepover
 ['2026-10-18','22:00','06:00',true,false,false],    // Sun sleepover
 ['2026-12-25','22:00','06:00',true,true,false],     // PH sleepover
 ['2026-10-14','22:00','07:30',true,false,true],     // OT sleepover
 ['2026-10-14','08:00','08:00',false,false,false],   // 24h
 ['2026-10-14','17:45','18:15',false,false,false],   // tiny evening boundary
];
const out: any = { pay: [], payCustomWindow: [], payCustomRates: [], invoice: null };
for (const c of cases) out.pay.push({ input: c, result: calculateShiftPay(c[0],c[1],c[2],c[3],DEFAULT_RATES,c[4],c[5]) });
for (const c of cases) out.payCustomRates.push({ input: c, result: calculateShiftPay(c[0],c[1],c[2],c[3],custom as any,c[4],c[5]) });
store['pref_evening_start']='18:00'; store['pref_evening_end']='22:00';
for (const c of cases) out.payCustomWindow.push({ input: c, result: calculateShiftPay(c[0],c[1],c[2],c[3],DEFAULT_RATES,c[4],c[5]) });
delete store['pref_evening_start']; delete store['pref_evening_end'];
const shifts = cases.filter(c=>!c[5]).map((c,i)=>{ const r = calculateShiftPay(c[0],c[1],c[2],c[3],DEFAULT_RATES,c[4],c[5]);
  return { id: `00000000-0000-0000-0000-${String(i).padStart(12,'0')}`, date:c[0], start_time:c[1], end_time:c[2], is_sleepover:c[3], is_public_holiday:c[4], is_overtime:c[5], gross_pay:r.grossPay, hours_worked:r.hoursWorked, fee_override: i===0 ? 500 : (i===9 ? 420 : null) }; });
out.invoiceShifts = shifts;
out.invoice = groupShiftsForInvoice(shifts as any, DEFAULT_RATES).map(g=>({category:g.category, quantity:g.quantity, totalHours:g.totalHours, rate:g.rate, subtotal:g.subtotal, shiftCount:g.shifts.length}));
console.log(JSON.stringify(out, null, 1));
