# XAU Trend Pullback EA (MQL5)

EA เทรดทองคำ XAUUSD แบบ **Trend Pullback + Market Structure** สำหรับ MetaTrader 5

> ⚠️ โค้ดนี้ทำขึ้นเพื่อการศึกษา **ยังไม่ได้ compile และยังไม่ได้ backtest** ต้อง compile ใน MetaEditor, backtest และทดสอบบน demo ก่อนใช้เงินจริงทุกครั้ง ผล backtest ไม่รับประกันผลในอนาคต

---

## 1. ไฟล์

ทั้ง EA อยู่ใน **ไฟล์เดียว: `XauTrendPullback.mq5`** (ใช้แค่ไลบรารีมาตรฐาน `Trade\Trade.mqh` ที่มากับ MT5 อยู่แล้ว)

ภายในไฟล์แบ่งเป็นหัวข้อ `SECTION:` ตามลำดับ:

| Section | หน้าที่ |
|---|---|
| Inputs | ค่าตั้งทั้งหมด (แบ่งกลุ่ม Risk / Structure / Regime / Entry / Exits / Sessions / News / Execution) |
| COMMON | Struct และฟังก์ชันช่วย (ราคา, lot, เวลา, Global Variables) |
| STRUCTURE | อ่านโครงสร้างตลาด: Swing (Fractal + ATR), BOS/CHoCH ยืนยันด้วยราคาปิด, Sweep, Impulse leg |
| REGIME | ระบุ Regime: TREND_UP / TREND_DOWN / RANGE / HIGH_VOL / DEAD |
| FILTERS | Session (เวลาเซิร์ฟเวอร์) + News filter (CSV และ MT5 Calendar) + Export ข่าวเป็น CSV |
| RISK | คำนวณ lot จากความเสี่ยง, Daily/Weekly/Max-DD lock, ลดความเสี่ยงเมื่อแพ้ติดกัน |
| EXECUTION | บริหารออเดอร์: TP1 + BE, Trailing, ออกเมื่อ CHoCH, Time stop, News exit, ปิดก่อน Rollover |
| SIGNAL | เงื่อนไขเข้า: H1 Fib zone + M15 CHoCH |
| OnInit / OnTick / OnTester | ส่วนควบคุมหลัก, Dashboard บนกราฟ, เกณฑ์ Custom สำหรับ optimize |

---

## 2. การติดตั้ง

1. เปิด MT5 → **File → Open Data Folder** → เข้าโฟลเดอร์ `MQL5/Experts/`
2. วางไฟล์ `XauTrendPullback.mq5` ลงไป
   - หรือใน MetaEditor: **File → New → Expert Advisor** ตั้งชื่อ `XauTrendPullback` แล้ววางโค้ดทั้งหมดทับ
3. เปิดไฟล์ใน MetaEditor (F4) → กด **Compile (F7)**
   - ถ้ามี error ให้ copy ข้อความจากแท็บ Errors มาให้แก้ได้เลย
4. เปิดกราฟ XAUUSD (แนะนำ M15) แล้วลาก EA ใส่กราฟ เปิด **Algo Trading**

> EA อ่าน H4, H1, M15 เองเสมอ ไม่ว่ากราฟที่เปิดจะเป็น timeframe อะไร

---

## 3. ตรวจเวลาเซิร์ฟเวอร์ของโบรกก่อน (สำคัญมาก)

ค่าเริ่มต้นของ session ตั้งไว้สำหรับโบรกที่ใช้ **เวลาเซิร์ฟเวอร์แบบ NY-close (GMT+2 ฤดูหนาว / GMT+3 ฤดูร้อน)** ซึ่งเป็นแบบที่โบรกส่วนใหญ่ใช้ และทำให้ตัวเลขคงที่ทั้งปีโดยไม่ต้องปรับ DST

| หน้าต่าง | เวลาเซิร์ฟเวอร์ (ค่าเริ่มต้น) | เวลาไทย (ช่วง DST / ฤดูหนาว) |
|---|---|---|
| London | 10:30–13:00 | 14:30–17:00 / 15:30–18:00 |
| New York (หลังข่าว 15:30) | 15:45–19:00 | 19:45–23:00 / 20:45–24:00 |
| Rollover (ห้ามเทรด/ปิดออเดอร์) | 23:30–01:30 | 03:30–05:30 / 04:30–06:30 |

**วิธีเช็ก:** ดูเวลาในหน้าต่าง Market Watch เทียบกับเวลาไทย
- ช่วง DST เวลาไทยควรเร็วกว่าเซิร์ฟเวอร์ 4 ชม. (ฤดูหนาว 5 ชม.)
- ถ้าไม่ตรง ให้แปลงเวลาเอง: `เวลาเซิร์ฟเวอร์ = เวลาไทย − 7 + GMT offset ของเซิร์ฟเวอร์`
- อีกวิธีที่ง่าย: ข่าว NFP/CPI (08:30 นิวยอร์ก) ต้องแสดงเป็น **15:30 เวลาเซิร์ฟเวอร์** ทั้งปี

---

## 4. ตั้งค่า News filter สำหรับ Backtest

ฟังก์ชัน Calendar ของ MT5 **ใช้ใน Strategy Tester ไม่ได้** จึงต้อง export ข่าวเป็นไฟล์ CSV ก่อน ฟังก์ชันนี้อยู่ใน EA แล้ว:

1. ลาก EA ใส่กราฟบนบัญชี demo/จริงที่เชื่อมต่ออยู่ ตั้ง `InpExportNewsCsv = true` และ `InpExportFrom` ให้ครอบคลุมช่วง backtest
2. ดูแท็บ Experts จะมีข้อความ `Exported N high-impact events ...`
3. ไฟล์จะถูกบันทึกที่ `Terminal\Common\Files\xau_news_usd.csv` จากนั้นจะถอด EA ออก หรือตั้ง `InpExportNewsCsv` กลับเป็น `false` ก็ได้
4. EA จะอ่านไฟล์นี้ทั้งตอน backtest และตอนเทรดจริง (ใช้เป็นตัวสำรอง)

รูปแบบไฟล์ (เวลาเซิร์ฟเวอร์) ถ้าจะทำเองจาก ForexFactory ให้ใช้รูปแบบเดียวกันนี้:
```
# time(server),currency,importance,event
2026.11.06 15:30,USD,HIGH,Non-Farm Employment Change
```

ตอนเทรดจริง EA จะดึงข่าวจาก MT5 Calendar เองทุก 1 ชม. และใช้ CSV เป็นตัวสำรอง

---

## 5. ตั้งค่า Strategy Tester ที่แนะนำ

| ค่า | ตั้งเป็น |
|---|---|
| Symbol | XAUUSD ของโบรกที่จะใช้จริง |
| Timeframe | M15 |
| Modelling | **Every tick based on real ticks** (เพื่อใช้ spread จริง) |
| ช่วงเวลา | 2020 – ปัจจุบัน (เผื่อข้อมูลก่อนหน้าอย่างน้อย 2 เดือนให้ H4/EMA200) |
| Deposit / Leverage | ตามบัญชีจริง |
| Optimization criterion | **Custom max** (ใช้ `OnTester` = PF × √จำนวนเทรด × (1 − DD%)) |

**Optimize แค่ 4–5 ตัว** เช่น `InpAdxMin`, `InpFibMax`, `InpMinRRRoom`, `InpTP2_R`, `InpTrailMode` แล้วใช้ Walk-forward (Forward = 1/4 ใน Tester)

**เกณฑ์ผ่าน:** Profit Factor > 1.3, Max DD < 15%, ≥ 200 เทรด, ผลยังเป็นบวกเมื่อเพิ่ม spread 50%

---

## 6. ลำดับการทำงานของ EA

```
ทุก tick   : อัปเดต Equity lock → TP1 (+1R ปิด 50%) → เลื่อน SL ไป Break-even
ทุกแท่ง M15 : วิเคราะห์โครงสร้าง H4/H1/M15 → Regime → บริหารออเดอร์
             (Rollover/Friday close, H1 CHoCH exit, Time stop, News exit, Trailing)
             → ถ้าไม่มีออเดอร์ + อยู่ใน session + ไม่มีข่าว + ไม่ติด lock → หา Entry
```

**เงื่อนไขเข้า Buy** (Sell กลับด้านทั้งหมด)
1. Regime = TREND_UP: H4 = BULL, ราคา > EMA200, EMA50 > EMA200, ADX(H1) ≥ 22, ATR ratio อยู่ในช่วง 0.6–1.8
2. H1 = BULL และมี impulse leg ล่าสุดที่อายุไม่เกิน 48 แท่ง H1
3. ราคาย่อ (ดูจาก M15) ถึงระดับ 38.2% ของ leg และยังไม่มีแท่ง H1 ปิดต่ำกว่า 61.8%
4. แท่ง M15 ล่าสุดปิดทะลุ swing high ภายในช่วงย่อ (M15 CHoCH)
5. SL = จุดต่ำสุดของการย่อ − 0.2×ATR(M15) (ขั้นต่ำ 1×ATR M15, ถ้ากว้างเกิน 2.5×ATR H1 ให้ข้าม)
6. ระยะถึง high ของ impulse ≥ 2R, spread ≤ 0.35 และ ≤ 10% ของ SL
7. Lot คำนวณจาก % ความเสี่ยงผ่าน `OrderCalcProfit` จึงรองรับ contract size ของทุกโบรก

---

## 7. ระบบป้องกันความเสี่ยง

| ระบบ | ค่าเริ่มต้น | การทำงาน |
|---|---|---|
| Risk ต่อไม้ | 0.5% | ปรับลดอัตโนมัติ: HIGH_VOL ×0.5, แพ้ 3 ไม้ติด ×0.5 (กลับเป็นปกติหลังชนะ 2 ไม้) |
| Daily lock | 2% | หยุดเปิดไม้ใหม่ถึงวันถัดไป |
| Weekly lock | 4% | หยุดเปิดไม้ใหม่ถึงสัปดาห์ถัดไป |
| Max DD lock | 10% จาก peak | **ปิดทุกออเดอร์และหยุด EA** ถ้าจะใช้ต่อต้องตั้ง `InpResetDDLock = true` |
| ไม่มี Martingale / Grid / ถัวขาดทุน | — | มีออเดอร์ได้ครั้งละ 1 ไม้ และมี SL ทุกไม้ |

สถานะต่างๆ เก็บใน Global Variables ของ terminal (prefix `XTP_<magic>_`) ปิดเปิด MT5 ใหม่แล้วยังอยู่ครบ

---

## 8. ข้อจำกัดที่ควรรู้

- โค้ดเขียนตาม spec แต่**ยังไม่ได้ compile และไม่ได้ทดสอบบน MT5 จริง** อาจมี compile error หรือ logic ที่ต้องปรับ
- ช่วง 1–2 สัปดาห์ต่อปีที่ยุโรปกับสหรัฐฯ เปลี่ยนเวลาไม่ตรงกัน หน้าต่าง London จะคลาดไป 1 ชม.
- Regime RANGE จะไม่เทรดเลย (ยังไม่มีโมดูลเล่นกรอบ)
- ใช้ EA นี้บนกราฟเดียวต่อ symbol/magic
- ก่อนใช้จริงให้ทดสอบบน demo 1–2 เดือน และเริ่มด้วย lot ขั้นต่ำ

*การเทรดทองคำด้วย leverage มีความเสี่ยงสูงที่จะสูญเสียเงินทุน ข้อมูลนี้ไม่ใช่คำแนะนำการลงทุน*
