/* HELUT radio C ABI — load with ctypes / GNU Radio OOT.
 *
 * Builds as libHELUTRadio.dylib (SPM dynamic product HELUTRadio).
 * Apple Silicon + Metal required for encrypted-demo mode; clear mode is CPU.
 *
 * Honest scope: this is a netlist tick surface for demos. It does not claim
 * production-N encrypted SING, and it is not a P1030680 decrypt path.
 */
#ifndef HELUT_H
#define HELUT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HELUT_OK              0
#define HELUT_ERR_ARGS       -1
#define HELUT_ERR_IO         -2
#define HELUT_ERR_NETLIST    -3
#define HELUT_ERR_MODE       -4
#define HELUT_ERR_TICK       -5
#define HELUT_ERR_BUFFER     -6
#define HELUT_ERR_INTERNAL   -7

typedef struct helut_engine helut_engine;

/** Library version string (static). */
const char *helut_version(void);

/**
 * Open a Yosys JSON netlist.
 *
 * mode:
 *   "clear"            — CleartextNetlistSimulator (boolean oracle; real-time OK)
 *   "encrypted-demo"   — EncryptedNetlistSimulator at N=8 (demo FHE path; slow)
 *
 * Returns NULL on failure; optional errbuf (may be NULL) gets a short message.
 */
helut_engine *helut_open(const char *netlist_path, const char *mode, char *errbuf, size_t errbuf_len);

void helut_close(helut_engine *engine);

/** Active mode string ("clear" / "encrypted-demo"), or NULL. */
const char *helut_mode(const helut_engine *engine);

/** Module name from the Yosys JSON. */
const char *helut_module_name(const helut_engine *engine);

int helut_input_port_count(const helut_engine *engine);
int helut_output_port_count(const helut_engine *engine);

/** Copy port name (NUL-terminated). Returns HELUT_OK or HELUT_ERR_*. */
int helut_input_port_name(const helut_engine *engine, int index, char *buf, size_t buflen);
int helut_output_port_name(const helut_engine *engine, int index, char *buf, size_t buflen);

int helut_input_port_width(const helut_engine *engine, int index);
int helut_output_port_width(const helut_engine *engine, int index);

/** Total packed bit widths (sum of port widths, ports sorted by name). */
int helut_input_bit_count(const helut_engine *engine);
int helut_output_bit_count(const helut_engine *engine);

/**
 * One netlist tick.
 *
 * in_bits / out_bits are packed bit arrays: one uint8_t per bit (0 or 1),
 * ports concatenated in lexicographic port-name order, LSB = bit index 0 of
 * that port (matches HELUT CleartextNetlistSimulator bit packing).
 */
int helut_tick(
    helut_engine *engine,
    const uint8_t *in_bits,
    size_t in_len,
    uint8_t *out_bits,
    size_t out_cap,
    size_t *out_len
);

/**
 * Sliding-window helper for regex_matcher (ports char0,char1,char2 → match).
 * Feeds one ASCII byte; emits *match ∈ {0,1} after each call once the window
 * is full. First two calls return HELUT_OK with *match = 0 (warming).
 */
int helut_regex_feed(helut_engine *engine, uint8_t byte, uint8_t *match);

/** Reset DFF state (clear / encrypted Q) to zeros. */
int helut_reset(helut_engine *engine);

#ifdef __cplusplus
}
#endif

#endif /* HELUT_H */
