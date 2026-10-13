# OK-J.E — Claude Skill สำหรับ Odoo 18 QA & เอกสาร

Skill `odoo-qa-docs` ใช้ให้ Claude ช่วยทำงาน Tester / Consultant / PM บนโปรเจกต์ Odoo 18 ในไทย:

| งาน | ได้อะไร | Export |
|---|---|---|
| Test Case (SIT) | ตาราง TC ครบ Positive / Negative / Boundary / Integration / Permission | Excel (มี dropdown Status) |
| UAT Script | Scenario ทางธุรกิจ + ตารางผลทดสอบ + หน้า Sign-off | Excel + Word |
| คู่มือการใช้งาน / SOP | ทีละขั้นตอน, เมนู, ที่วางภาพ, FAQ | Word (ฟอนต์ TH Sarabun New) |
| Bug Report | แปลงโน้ตของ tester เป็นรายงานมาตรฐาน | Markdown |

## โครงสร้าง
```
.claude/skills/odoo-qa-docs/
├── SKILL.md            # กฎหลัก + ตัวเลือกโหมด (สั้นที่สุด)
├── templates/          # โหลดเฉพาะโหมดที่ใช้
├── modules/            # ความรู้ Odoo 18 รายโมดูล: sales, purchase, inventory, accounting-th, mrp, pos, crm
└── scripts/export.py   # md → xlsx/docx (Claude สั่งรัน ไม่ต้องอ่านโค้ด)
docs/examples/          # ตัวอย่างผลลัพธ์
```

## วิธีใช้
เปิด Claude Code ในโฟลเดอร์นี้ (หรือคัดลอก `.claude/skills/odoo-qa-docs` ไปไว้ที่ `~/.claude/skills/` เพื่อใช้ได้ทุกโปรเจกต์) แล้วสั่งตามปกติ เช่น:

- `ทำ test case Sales: quotation → delivery → invoice แบบ delivered qty, export excel`
- `ทำ UAT script Purchase two-step approval วงเงิน 50,000`
- `เขียนคู่มือรับสินค้าและตรวจนับสต็อก สำหรับ user คลัง`
- `แปลงเป็น bug report: กด validate DO แล้ว error lot required ทั้งที่ใส่แล้ว`

แนบ BRD / FSD / Fit-Gap ได้ — Skill จะใช้ requirement ของลูกค้าก่อน standard เสมอ

## ทำไมประหยัด Token
1. **Progressive loading** — Claude เห็นแค่ชื่อและคำอธิบาย Skill จนกว่าจะเรียกใช้ จากนั้นโหลดเฉพาะ template 1 ไฟล์ + โมดูลที่เกี่ยวข้อง ไม่โหลดทั้งหมด
2. **คำสั่งภายในเป็นภาษาอังกฤษ** (ภาษาไทยใช้ token มากกว่าหลายเท่า) แต่ผลลัพธ์ออกเป็นภาษาไทย
3. **ห้าม preamble / ห้ามทวนโจทย์** ตอบเป็นตาราง, precondition และ test data ที่ใช้ซ้ำเขียนครั้งเดียว
4. **งานใหญ่เขียนลงไฟล์** ตอบกลับแค่ path + จำนวน ไม่พิมพ์เนื้อหาซ้ำในแชท
5. **Export ด้วยสคริปต์** — ไม่ต้องให้ Claude สร้าง Excel/Word เอง

## ปรับแต่ง
- เพิ่มโมดูล: สร้าง `modules/<name>.md` รูปแบบเดียวกัน (เมนู, flow, settings, checklist) แล้วเพิ่มชื่อใน `SKILL.md`
- เปลี่ยนรูปแบบ Word: แก้ `scripts/reference.docx` (styles/ฟอนต์/โลโก้ header)
- ใส่ requirement ประจำโปรเจกต์ เช่น การตั้งชื่อ TC หรือ role ของลูกค้า ไว้ใน `SKILL.md` ส่วน Defaults
