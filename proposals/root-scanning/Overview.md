# Proposal: Linear-Memory GC-Root Marking

## Overview (Copied from https://github.com/WebAssembly/design/issues/1459)

A frequent request has been to provide better support for implementing garbage collection in linear memory.
At present, the main obstacle is the inability to scan the WebAssembly stack for GC roots, as is standard in GC implementations.
This proposal outlines a way to efficiently, safely, and compactly support such functionality.

Illustrative Example

The following is the outline of a module using the new proposal to scan the stack for linear-memory GC roots.

(module
  (memory ...)
  (local-mark $gc_root i32)
  ...
  (func $example_method_implementation
    (param $this_pointer i32)
    (local $array_index i32)
    (local $array_pointer i32)
    (marked-locals $gc_root $this_pointer $array_pointer) ; not $array_index
    ... ;; instructions implementing method body
  )
  ...
  (func $mark_gc_root
    (param $gc_root i32)
    ... ;; instructions for the GC's gc-root-marking process
  )
  ...
  (func $scan_for_gc_roots
    (enumerate-marked-locals $gc_root $repeat_with_next_marked_local
      (call $mark_gc_root) ;; the value of the marked local is on the stack
      (br $repeat_with_next_marked_local)
    end)
  )
  ...
)
In this module, there are three new constructs:

local-mark: part of the tag section; declares a new mark (whose index is referenced by $gc_root) that can be attributed to locals of type i32
marked-locals: optionally immediately follows the declaration of locals, specifying a mark (in this case $gc_root) and a list of locals the mark should be applied to (in this case $this_pointer and $array_pointer)
enumerate_marked_locals: an instruction block whose body is executed with the value of the most immediately enclosing local marked with the specified mark (in this case $gc_root); the instruction introduces a label (referenced by $repeat_with_next_marked_local) that is branched to in order to repeat the body with the next-most enclosing $gc_root-marked local (exiting the block if there isn't one)
Taken all together, the effect of these constructs is that, if $scan_for_gc_roots is called during the execution of $example_method_implementation, then eventually the values of $this_pointer and $array_pointer will each be passed as the argument to calls to $mark_gc_root.

Design Overview

In order to make the feature efficient and compact, the key insight is that locals in a function conceptually describe the stack frame of the function.
There are safety and performance issues with letting one examine this stack frame arbitrarily, but we can address those issues by explicitly marking which locals can be examined.

The tag section is extended to include local marks (local-mark $mark (type mutable?)), which each specify the type of local the newly defined mark can apply to and can optionally indicate that the mark is mutable.

A function header, then, is extended to optionally specify a local-marking list: (mark-locals $mark local_idx+)? (where each local_idx list is strictly ascending).
This list indicates which locals in the frame have been marked and with which mark.
The requirement is that the type of each specified local must match the associated type of the mark (a subtype if the mark is not mutable, and exactly if the mark is mutable).

Lastly, the instruction set is extended with the instruction enumerate_marked_locals $mark instr* end : [] -> [].
If t is the associated type of $mark, then the body instructions instr* must have type [t] -> [].
The body instructions are also given access to a label of type [] and, if $mark is mutable, a label of type [t]; in the example, the former label is referenced by $repeat_with_next_marked_local.
enumerate_marked_locals searches the stack for the first enclosing label tagged with $mark and hands its current value to instr*.
If instr* branches to the provided label of type [], then the stack is searched for the next appropriate local and instr* is executed with its current value.
If instr* branches to the provided label of type [t], the value of the current local at hand is updated and then the stack is searched for the next appropriate local and instr* is executed with with its current value.
If at any point there are no more appropriate locals, or the end of instr* is reached, then control jumps to end, thereby exiting the loop.

Application: Garbage Collection

This feature is focused on garbage collection, for which language runtimes implemented in WebAssembly generally want root-scanning to be very efficient.
The feature is designed so that no function calls or non-local control transfers are required during the scan.
The feature is also designed so that it is easy for engines to easily and compactly decorate the stack with the information necessary to determine where the roots are in its representation of the stack frame, and so that engines can freely optimize unmarked locals as before.
The example above illustrates how one can use this feature to implement a 32-bit garbage collector.
In the case of a moving GC, one uses a mutable mark, and $scan_for_gc_roots updates the local to the new address of the data.
Note that the language runtime implemented in WebAssembly is responsible for ensuring its garbage collector is run sufficiently often.

Extension: Concurrent Garbage Collection
The stack-switching proposal adds the possibility of concurrent garbage collection.
To support this, this proposal would furthermore add enumerate_marked_locals_in_task/stack/fibre/continuation $gc_root instr* end : [taskref/stackref/fibreref/contref] -> [], which enumerates all the locals on a suspended stack (which is locked until the loop is exited).

Proposal Process: Phase 0

Do not take this as a final design; there are many variations on and questions for this design. This write-up is meant as a starting point should the community decide there is enough interest in the overall direction to advance the proposal to Phase 1. (And thanks to those who already provided suggestions on how to improve this write-up!) The primary purpose of this thread is to gauge interest as well as to collect high-level concerns that should be addressed or kept in consideration.
