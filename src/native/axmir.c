/* axmir: a thin shim over MIR's C API for Axon, compiled into mir.dll /
   libmir.dylib together with mir.c and mir-gen.c (tools/mir/CMakeLists.txt).

   Delphi calls MIR's pointer-and-integer functions directly. This shim covers
   the rest, so the Delphi side never depends on C struct layout:

   - Operands. MIR_op_t uses enum bitfields, whose layout differs between
     MSVC and clang, and MIR returns it by value. Delphi passes operands as
     axmir_op, a plain fixed-layout record, and the shim builds the MIR_op_t
     array for MIR_new_insn_arr.
   - Registers and function addresses, which need fields of MIR_item.
   - Errors. MIR's default error function exits the process. The shim's
     formats the message and passes it to a handler set from Delphi, which
     must not return; if none is set, it prints the message and exits with
     code 3 (an internal error).
   - Instruction codes, looked up by name so the Delphi side does not
     hard-code the ordinals of MIR_insn_code_t. */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mir.h"
#include "mir-gen.h"

#ifdef _WIN32
#define AXMIR_API __declspec (dllexport)
#else
#define AXMIR_API __attribute__ ((visibility ("default")))
#endif

/* Operand kinds of axmir_op. */
enum { AXOP_REG, AXOP_INT, AXOP_DOUBLE, AXOP_REF, AXOP_LABEL, AXOP_MEM };

/* 48 bytes, no bitfields, the same layout on every target. */
typedef struct {
  int32_t kind;
  int32_t type;   /* AXOP_MEM: MIR_type_t of the memory */
  int64_t i;      /* AXOP_INT: value; AXOP_MEM: displacement */
  double d;       /* AXOP_DOUBLE */
  void *p;        /* AXOP_REF: MIR_item_t; AXOP_LABEL: MIR_label_t */
  uint32_t reg;   /* AXOP_REG: register; AXOP_MEM: base register (0 = none) */
  uint32_t index; /* AXOP_MEM: index register (0 = none) */
  uint32_t scale; /* AXOP_MEM: index scale (1, 2, 4 or 8) */
  uint32_t pad;
} axmir_op;

typedef void (*axmir_error_handler) (int error_type, const char *message);

static axmir_error_handler error_handler = NULL;

static void MIR_NO_RETURN axmir_error (MIR_error_type_t error_type, const char *format, ...) {
  char message[1024];
  va_list args;
  va_start (args, format);
  vsnprintf (message, sizeof (message), format, args);
  va_end (args);
  if (error_handler != NULL) error_handler ((int) error_type, message);
  fprintf (stderr, "InternalError: MIR: %s\n", message);
  fflush (stderr);
  exit (3);
}

AXMIR_API int axmir_op_size (void) { return (int) sizeof (axmir_op); }

AXMIR_API void axmir_set_error_handler (axmir_error_handler handler) { error_handler = handler; }

/* A context with the generator ready, at the given optimisation level (0-3;
   MIR's default is 2). */
AXMIR_API MIR_context_t axmir_init (unsigned int optimize_level) {
  MIR_context_t ctx = MIR_init ();
  MIR_set_error_func (ctx, axmir_error);
  MIR_gen_init (ctx);
  MIR_gen_set_optimize_level (ctx, optimize_level);
  return ctx;
}

AXMIR_API void axmir_finish (MIR_context_t ctx) {
  MIR_gen_finish (ctx);
  MIR_finish (ctx);
}

/* The code of the instruction named name ("add", "dmov", "ret" …), or -1. */
AXMIR_API int axmir_insn_code (MIR_context_t ctx, const char *name) {
  for (int code = 0; code < MIR_INSN_BOUND; code++)
    if (strcmp (MIR_insn_name (ctx, (MIR_insn_code_t) code), name) == 0) return code;
  return -1;
}

/* A new local register of func (an item made by MIR_new_func_arr). */
AXMIR_API MIR_reg_t axmir_new_reg (MIR_context_t ctx, MIR_item_t func, int type,
                                   const char *name) {
  return MIR_new_func_reg (ctx, func->u.func, (MIR_type_t) type, name);
}

/* The register of a parameter or local of func, by name. */
AXMIR_API MIR_reg_t axmir_reg (MIR_context_t ctx, MIR_item_t func, const char *name) {
  return MIR_reg (ctx, name, func->u.func);
}

static MIR_op_t to_op (MIR_context_t ctx, const axmir_op *op) {
  switch (op->kind) {
  case AXOP_REG: return MIR_new_reg_op (ctx, op->reg);
  case AXOP_INT: return MIR_new_int_op (ctx, op->i);
  case AXOP_DOUBLE: return MIR_new_double_op (ctx, op->d);
  case AXOP_REF: return MIR_new_ref_op (ctx, (MIR_item_t) op->p);
  case AXOP_LABEL: return MIR_new_label_op (ctx, (MIR_label_t) op->p);
  case AXOP_MEM:
    return MIR_new_mem_op (ctx, (MIR_type_t) op->type, op->i, op->reg, op->index,
                           (MIR_scale_t) op->scale);
  default: axmir_error (MIR_wrong_param_value_error, "axmir: unknown operand kind %d", op->kind);
  }
}

/* An instruction from nops operands (not yet appended to a function). */
AXMIR_API MIR_insn_t axmir_new_insn (MIR_context_t ctx, int code, size_t nops,
                                     const axmir_op *ops) {
  MIR_op_t buf[16];
  MIR_op_t *mops = nops <= 16 ? buf : (MIR_op_t *) malloc (nops * sizeof (MIR_op_t));
  MIR_insn_t insn;
  for (size_t k = 0; k < nops; k++) mops[k] = to_op (ctx, &ops[k]);
  insn = MIR_new_insn_arr (ctx, (MIR_insn_code_t) code, nops, mops);
  if (mops != buf) free (mops);
  return insn;
}

/* Links the loaded modules, generating machine code for every function. */
AXMIR_API void axmir_link (MIR_context_t ctx) { MIR_link (ctx, MIR_set_gen_interface, NULL); }

/* The address to call a function item at, after axmir_link. */
AXMIR_API void *axmir_func_addr (MIR_item_t func) { return func->addr; }

/* Writes the textual MIR of everything in ctx to stderr (for debugging). */
AXMIR_API void axmir_dump (MIR_context_t ctx) {
  MIR_output (ctx, stderr);
  fflush (stderr);
}
