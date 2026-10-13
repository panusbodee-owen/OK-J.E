# Template: User Manual / SOP (คู่มือการใช้งาน)

Audience: end users (Thai). Short sentences, imperative ("กดปุ่ม **Confirm**"). One process per chapter. No theory — only what the user clicks and checks.

## Output format

```
# คู่มือการใช้งาน Odoo 18 — <Module>
| โครงการ | <name> | เวอร์ชันเอกสาร | 1.0 | วันที่ | <yyyy-mm-dd> | ผู้จัดทำ | |
|---|---|---|---|---|---|---|---|

## สารบัญ
1. <Process 1>
2. <Process 2>

## 1. <Process name>
**วัตถุประสงค์:** <1 line>
**ผู้ใช้งาน / สิทธิ์:** <role> (<Odoo group>)
**เมนู:** `Sales > Orders > Quotations`
**ก่อนเริ่ม:** <master data / settings ที่ต้องมี>

### ขั้นตอน
| # | การทำงาน | หมายเหตุ |
|---|---|---|
| 1 | ไปที่เมนู `Sales > Orders > Quotations` กด **New** | ![ภาพ 1.1](images/1-1.png) |
| 2 | ระบุ **Customer** | ฟิลด์บังคับ |
| 3 | แท็บ **Order Lines** กด **Add a product** เลือกสินค้า ระบุ **Quantity** | ราคาดึงจาก Pricelist อัตโนมัติ |
| 4 | กด **Confirm** | สถานะเปลี่ยนเป็น Sales Order |

### ผลลัพธ์ที่ต้องตรวจสอบ
- <สถานะ/เอกสารที่ถูกสร้าง/ตัวเลขที่ต้องเห็น>

### ข้อควรระวัง / FAQ
- **ถาม:** ... **ตอบ:** ...
```

## Rules
- Screenshot placeholders: `![ภาพ <chapter>.<n>](images/<chapter>-<n>.png)` — only where the screen changes, max 1 per 2 steps.
- Field/button names exactly as Odoo 18 UI (English) — Thai explanation in the Remark column if needed.
- Customer-specific fields (Studio/custom module): mark `(Custom)`.
- End chapter with result-check list; end document with a glossary only if user asks.
