# OK-J.E — Claude Skill สำหรับ Odoo QA & เอกสาร (ทุกเวอร์ชัน)

Skill `odoo-qa-docs` ใช้ให้ Claude ช่วยทำงาน Tester / Consultant / PM บนโปรเจกต์ Odoo ในไทย รองรับ v16–v19 และเวอร์ชันในอนาคต (v20+):

| งาน | ได้อะไร | Export |
|---|---|---|
| Test Case (SIT) | ตาราง TC ครบ Positive / Negative / Boundary / Integration / Permission | Excel (มี dropdown Status) |
| UAT Script | Scenario ทางธุรกิจ + ตารางผลทดสอบ + หน้า Sign-off | Excel + Word |
| คู่มือการใช้งาน / SOP | ทีละขั้นตอน, เมนู, ที่วางภาพ, FAQ | Word (ฟอนต์ TH Sarabun New) |
| Bug Report | แปลงโน้ตของ tester เป็นรายงานมาตรฐาน | Markdown |
| Upgrade Regression | กระทบยอดข้อมูลก่อน/หลังอัปเกรด + TC ตามจุดที่เปลี่ยน | Excel |

## โครงสร้าง
```
.claude/skills/odoo-qa-docs/
├── SKILL.md            # กฎหลัก + ตัวเลือกโหมด (สั้นที่สุด)
├── templates/          # โหลดเฉพาะโหมดที่ใช้
├── modules/            # ความรู้รายโมดูล (ฐาน = v18): sales, purchase, inventory, accounting-th, mrp, pos, crm
├── versions/           # เฉพาะ "ส่วนต่าง" ของแต่ละเวอร์ชัน: v17, v18, v19, _new-version.md
└── scripts/export.py   # md → xlsx/docx (Claude สั่งรัน ไม่ต้องอ่านโค้ด)
docs/examples/          # ตัวอย่างผลลัพธ์
```

## วิธีใช้
เปิด Claude Code ในโฟลเดอร์นี้ (หรือคัดลอก `.claude/skills/odoo-qa-docs` ไปไว้ที่ `~/.claude/skills/` เพื่อใช้ได้ทุกโปรเจกต์) แล้วสั่งตามปกติ เช่น:

- `ทำ regression test อัปเกรด Odoo 17 → 18 โมดูล Inventory`
- `ทำ test case Sales: quotation → delivery → invoice แบบ delivered qty, export excel`
- `ทำ UAT script Purchase two-step approval วงเงิน 50,000`
- `เขียนคู่มือรับสินค้าและตรวจนับสต็อก สำหรับ user คลัง`
- `แปลงเป็น bug report: กด validate DO แล้ว error lot required ทั้งที่ใส่แล้ว`

แนบ BRD / FSD / Fit-Gap ได้ — Skill จะใช้ requirement ของลูกค้าก่อน standard เสมอ

## รองรับ Odoo เวอร์ชันอนาคต
- `modules/` เขียนครั้งเดียวเป็นฐาน v18 ส่วน `versions/vNN.md` เก็บ **เฉพาะสิ่งที่ต่างจากฐาน** จึงโหลดน้อยและแก้ที่เดียว
- เจอเวอร์ชันใหม่ที่ยังไม่มีไฟล์ (เช่น v20) Skill จะ: ทำงานต่อด้วยฐาน v18 → ติดป้าย `(verify)` ทุกชื่อเมนูที่ยังไม่ยืนยัน → ตรวจจาก screenshot / release notes / ระบบจริง → บันทึกสิ่งที่ยืนยันแล้วลง `versions/v20.md` ครั้งต่อไปไม่ต้องตรวจซ้ำ
- เมื่อบริษัทย้ายไปใช้เวอร์ชันใหม่เป็นหลัก สามารถเลื่อนเวอร์ชันนั้นเป็นฐานใหม่ได้ (ดู `versions/_new-version.md`)
- `v19.md` ตอนนี้สถานะ PARTIAL — ยังไม่ได้ยืนยันกับระบบ v19 จริง

## ทำไมประหยัด Token
1. **Progressive loading** — Claude เห็นแค่ชื่อและคำอธิบาย Skill จนกว่าจะเรียกใช้ จากนั้นโหลดเฉพาะ template 1 ไฟล์ + ไฟล์เวอร์ชัน 1 ไฟล์ + โมดูลที่เกี่ยวข้อง
2. **คำสั่งภายในเป็นภาษาอังกฤษ** (ภาษาไทยใช้ token มากกว่าหลายเท่า) แต่ผลลัพธ์ออกเป็นภาษาไทย
3. **ห้าม preamble / ห้ามทวนโจทย์** ตอบเป็นตาราง, precondition และ test data ที่ใช้ซ้ำเขียนครั้งเดียว
4. **งานใหญ่เขียนลงไฟล์** ตอบกลับแค่ path + จำนวน ไม่พิมพ์เนื้อหาซ้ำในแชท
5. **Export ด้วยสคริปต์** — ไม่ต้องให้ Claude สร้าง Excel/Word เอง

## ปรับแต่ง
- เพิ่มโมดูล: สร้าง `modules/<name>.md` รูปแบบเดียวกัน (เมนู, flow, settings, checklist) แล้วเพิ่มชื่อใน `SKILL.md`
- เปลี่ยนรูปแบบ Word: แก้ `scripts/reference.docx` (styles/ฟอนต์/โลโก้ header)
- ใส่ requirement ประจำโปรเจกต์ เช่น การตั้งชื่อ TC หรือ role ของลูกค้า ไว้ใน `SKILL.md` ส่วน Defaults
