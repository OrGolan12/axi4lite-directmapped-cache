# core_translator_tb Waveform Explanation

This waveform shows the **AW → AR → W** ordering scenario with the CPU not ready to accept responses immediately.  
It tests that:
- Reads can bypass an incomplete write (AW received but W not yet sent).
- The DUT holds R/B channel valid until the CPU asserts ready.

---

<img width="1709" height="577" alt="image" src="https://github.com/user-attachments/assets/63d84e05-3bc7-47fb-842f-52cc843a925b" />


---

## Timeline

### 0) Reset & Idle
- `rst_n` starts low, then goes high after 5 cycles.
- All signals are 0 or X.
- `core_req_ready = 1` → core always ready to accept requests.

---

### 1) Write Address (AW)
- At **T=5 cycles**, `s_awaddr = 0x00000000`, `s_awvalid = 1`.
- `s_awready = 1` → handshake occurs in the same cycle.
- Write FSM (`dbg_w_state`) moves from **IDLE** to **HAVE_AW**.
- No data yet, so write is not issued to core.

---

### 2) Read Address (AR)
- Later, `s_araddr = 0x00000010`, `s_arvalid = 1`.
- Handshakes immediately with `s_arready = 1`.
- Read FSM (`dbg_r_state`) goes **IDLE → ISSUE**.
- DUT sends core request:
  - `core_req_valid = 1`, `core_req_we = 0` (read).
  - `core_req_addr = 0x00000010`.
- Core accepts instantly (`core_req_ready = 1`).

---

### 3) Write Data (W)
- `s_wdata = 0xDEADBEEF`, `s_wstrb = 0xF`, `s_wvalid = 1`.
- Handshake with `s_wready = 1` → DUT now has AW + W.
- Write request issued to core:
  - `core_req_valid = 1`, `core_req_we = 1` (write).
  - `core_req_addr = 0x00000000`, `core_req_wdata = 0xDEADBEEF`.

---

### 4) Core Read Response
- Core sends `core_resp_valid = 1`, `core_resp_is_write = 0`.
- Data: `core_resp_rdata = 0x12345678`, `core_resp_resp = 00` (OKAY).
- DUT drives R channel to CPU:
  - `s_rvalid = 1`, `s_rdata = 0x12345678`, `s_rresp = 00`.
- Since `s_rready = 0`, DUT holds data valid (sticky response).

---

### 5) Core Write Response
- Later, core sends `core_resp_valid = 1`, `core_resp_is_write = 1`.
- `core_resp_resp = 00` (OKAY).
- DUT drives B channel:
  - `s_bvalid = 1`, `s_bresp = 00`.
- Since `s_bready = 0`, DUT holds B channel valid until handshake.

---

## Key Points Verified
- Read can bypass incomplete write (AW before W).
- DUT holds `s_rvalid` and `s_bvalid` until handshake when CPU not ready.
- FSMs (`dbg_r_state`, `dbg_w_state`) reflect correct transitions:
  - **Read**: IDLE → ISSUE → WAIT_RESP → IDLE
  - **Write**: IDLE → HAVE_AW → ISSUE → WAIT_B → IDLE
