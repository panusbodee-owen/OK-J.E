# XAU_SweepCHoCH_EA (MQL5)

EA สำหรับ XAUUSD ตามพิมพ์เขียว "ท่าเดิม ต้นทุนต่ำ" — ท่า **Liquidity Sweep + CHoCH + FVG**

## การติดตั้ง
1. คัดลอก `Experts/XAU_SweepCHoCH_EA.mq5` ไปที่ `MQL5/Experts/` ของ MT5
2. Compile ใน MetaEditor (F7) แล้วลากใส่กราฟ XAUUSD (TF ใดก็ได้ EA ใช้ M5/M15/H1/D1 เอง)
3. เปิด Algo Trading

## State Machine 6 สถานะ
| State | การทำงาน |
|---|---|
| 1 IDLE & FILTER | Killzone (14:00–17:00, 19:00–22:30 ไทย), Spread ≤ 40, ข่าวแดง USD ±30 นาที, Circuit breaker, ศุกร์หลัง 22:00/จันทร์ก่อน 14:00 |
| 2 LIQUIDITY SWEEP | แท่ง M15 ทะลุ Asian H/L, PDH/PDL หรือ Swing H1 ไม่เกิน 1.5×ATR(M15) แล้วปิดกลับเข้ากรอบภายใน 1–2 แท่ง |
| 3 CHoCH CONFIRM | ภายใน 15 แท่ง M5 ปิดทะลุ Swing ย่อยฝั่งตรงข้าม + เกิด FVG; ยกเลิกถ้าทำ extreme ใหม่ |
| 4 RISK & LIMIT | Entry ใน FVG, SL = ปลายไส้ ± 0.2×ATR(M5), SL 180–600 จุด, Lot ตาม Risk %, TP 3R |
| 5 ORDER ACTIVE | ลบ Limit ถ้าไม่ถูกเกี่ยวใน 12 แท่ง M5 หรือราคาไปถึง 2R ก่อน |
| 6 TRADE MGMT | ถึง 1.5R ปิด 50% + SL บังทุน, จากนั้นเลื่อน SL ตาม Swing M15; แพ้ก่อน 1.5R นับเป็นไม้แพ้ |

Circuit breaker: แพ้ติดกัน 2 ไม้ หรือ Equity ลด 2% ของยอดต้นวัน → หยุดถึงวันใหม่ (ตามเวลาไทย)

## ข้อควรรู้เรื่องเวลา
- ทุกเวลาใน Input เป็น **เวลาไทย** EA แปลงเป็นเวลา Server ให้เอง
- Live: คำนวณ GMT offset ของ Server อัตโนมัติ
- **Strategy Tester: ต้องตั้ง `InpServerGMTOffset` ให้ตรงโบรกเกอร์** (ส่วนมาก 2 หน้าหนาว / 3 หน้าร้อน)
- `InpWinterShift` เลื่อนช่วงตลาดช้าลง 1 ชม. ช่วง พ.ย.–มี.ค. ตามเอกสาร
- News filter ใช้ MQL5 Economic Calendar ซึ่ง **ไม่ทำงานใน Tester** (ถูกข้ามอัตโนมัติ)

## ข้อจำกัด / ที่ยังไม่ทำ
- ยืนยัน CHoCH ด้วย FVG เท่านั้น (ยังไม่ใช้ Order Block)
- โหมด Trend Pullback (Fibo 61.8–78.6% + Engulfing/Pin bar) และ Breakout & Retest ยังไม่ได้ทำ — ใช้ได้แค่ตัวกรอง Premium/Discount (`InpUseEquilibrium`)
- ยังไม่ได้ Compile/Backtest จริงใน MT5 — ควรทดสอบบนบัญชี Demo ก่อน
