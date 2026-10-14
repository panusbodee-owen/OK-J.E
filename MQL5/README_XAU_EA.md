# XAU_SweepCHoCH_EA (MQL5)

EA สำหรับ XAUUSD ตามพิมพ์เขียว "ท่าเดิม ต้นทุนต่ำ" — รวม 3 ท่า เปิด/ปิดแยกได้ (`InpUseSetup1/2/3`)

| ท่า | เงื่อนไข | เข้าออเดอร์ |
|---|---|---|
| S1 Liquidity Sweep + CHoCH | ตาม State Machine ด้านล่าง | Limit ใน FVG |
| S2 Trend Pullback + OB | H1 เป็น HH/HL (หรือ LH/LL), ราคาย่อเข้าโซน Fibo 61.8–78.6% ของขาล่าสุด ที่ซ้อนทับ Order Block H1, แท่ง M15 ปิดเป็น Engulfing/Pin Bar (เลือกให้ H4 ต้องไปทางเดียวกันได้) | Market, SL หลังโซน, 1 ไม้ต่อ 1 ขาราคา |
| S3 Breakout & Retest | แท่ง M15 Momentum (เนื้อ ≥ 1×ATR) เบรก Asian H/L, PDH/PDL หรือ Swing H1 หลังสะสมพลัง 16 แท่ง; ไม่ไล่ราคา รอ Retest แนว + แท่ง M5 ปฏิเสธราคาภายใน 16 แท่ง M15; ยกเลิกถ้าปิดกลับเข้ากรอบ (เบรกหลอก) | Market, SL หลังแนวที่เบรก, ค่าเริ่มต้นเข้าเฉพาะ NY Killzone |

ทุกท่าใช้ตัวกรอง, ช่วง SL 180–600 จุด, TP 3R, Partial/BE/Trailing และ Circuit breaker ชุดเดียวกัน — เปิดได้ครั้งละ 1 ไม้

## ความเสี่ยงต่อไม้
- `InpRiskMode = % ของ Balance` → ใช้ `InpRiskPercent`
- `InpRiskMode = ยอดเงินคงที่ต่อไม้` → ใช้ `InpRiskMoney` (เช่น 5 = เสี่ยง 5$ ต่อไม้ทุกไม้ ไม่ว่าพอร์ตเท่าไร)
- ถ้า Lot ที่คำนวณได้ต่ำกว่า Lot ขั้นต่ำ EA จะข้ามไม้นั้น เว้นแต่เปิด `InpAllowMinLot` (ความเสี่ยงจริงจะเกินที่ตั้ง และพิมพ์แจ้งใน Log)
- ตัวอย่าง XAUUSD: 0.01 lot, SL 500 จุด ≈ 5$ → ตั้ง 5$ จะได้ SL ได้ไม่เกิน ~500 จุดที่ 0.01 lot
- เปลี่ยนค่าได้ตลอดผ่านหน้าต่าง Inputs (F7 บนกราฟ) มีผลกับไม้ถัดไป
- Circuit breaker รายวันตั้งเป็นเงินได้ด้วย `InpMaxDailyLossMoney` (0 = ปิด)

## การติดตั้ง
1. คัดลอก `Experts/XAU_SweepCHoCH_EA.mq5` ไปที่ `MQL5/Experts/` ของ MT5
2. Compile ใน MetaEditor (F7) แล้วลากใส่กราฟ XAUUSD (TF ใดก็ได้ EA ใช้ M5/M15/H1/D1 เอง)
3. เปิด Algo Trading

## State Machine 6 สถานะ (ท่า S1)
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
- ยังไม่ได้ Compile/Backtest จริงใน MT5 — ควรทดสอบบนบัญชี Demo ก่อน
