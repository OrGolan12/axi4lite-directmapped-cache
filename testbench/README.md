# core_translator_tb – Waveform Notes

The waveform below shows the AW → AR → W ordering case with the CPU not ready to take responses right away.  
This scenario checks two main things:

- A read request can bypass a pending write if only the write address (AW) has been received.
- The design holds R/B channel valid until the CPU side asserts ready.

---

<img width="1707" height="567" alt="image" src="https://github.com/user-attachments/assets/b0b7b234-4185-4ac7-9979-9f567e2fde88" />


---

## Sequence

**Reset**  
`rst_n` is low for the first few cycles, then released. Core is always ready (`core_req_ready = 1`).

**1. Write address (AW)**  
At ~T+5 cycles, `s_awaddr = 0x00000000` and `s_awvalid` goes high for one cycle.  
With `s_awready = 1`, the handshake completes immediately. The write FSM moves to HAVE_AW, waiting for the write data.

**2. Read address (AR)**  
A few cycles later, `s_araddr = 0x00000010` and `s_arvalid` go high.  
The handshake with `s_arready = 1` triggers a core read request (`core_req_valid = 1`, `we = 0`).  
The core accepts it in the same cycle.

**3. Write data (W)**  
`s_wdata = 0xDEADBEEF`, `s_wstrb = 0xF`, `s_wvalid = 1`.  
With `s_wready = 1`, the DUT now has both AW and W and issues the write to the core (`we = 1`).

**4. Core read response**  
Core responds with `core_resp_rdata = 0x12345678`, `resp = OKAY`.  
DUT drives `s_rvalid = 1`, `s_rdata = 0x12345678`.  
Since `s_rready = 0`, R channel stays valid until the CPU takes it.

**5. Core write response**  
Later, core responds to the write (`core_resp_is_write = 1`, `resp = OKAY`).  
DUT drives `s_bvalid = 1`, `s_bresp = 00`.  
With `s_bready = 0`, B channel remains valid until the handshake.

---

**Verified in this run:**
- Read can bypass incomplete write (AW without W).
- R and B channels hold valid when CPU isn’t ready.
- FSMs transition as expected:
  - Read: IDLE → ISSUE → WAIT_RESP → IDLE
  - Write: IDLE → HAVE_AW → ISSUE → WAIT_B → IDLE
