;; -*- geiser-scheme-implementation: chez -*-
;;; rv64.ss
;;; Copyright 2020 Paulo Matos <pmatos@linki.tools>
;;; 
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;; 
;;; http://www.apache.org/licenses/LICENSE-2.0
;;; 
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

;;; SECTION 1: registers
;;; ABI:
;;;  Register usage:
;;;   x0 aka zero: Hardwired zero
;;;   x1 aka ra: return address
;;;   x2 aka sp: C stack pointer
;;;   x3 aka gp: global pointer
;;;   x4 aka tp: thread pointer
;;;   x5-x7,x28-x31 aka t0-t6: Temporaries
;;;   x10-x17 aka a0-a7: C argument registers where x10,x11 aka a0,a1 are return values
;;;   x7 aka s0 aka fp: frame pointer
;;;   x9,x18-x27 aka s1-s11: saved register
;;;
;;;   saved registers are preserved across a function call, temporaries are not
;;;   --------
;;;   Support for floating point comes from F and D extensions respectively
;;;   There a new 32-long registerbank for floating point registers.
;;;   f0-f7,f28-f31 aka ft0-ft11: FP temporaries (12 registers)
;;;   f8,f9,f18-f27 aka fs0-fs11: FP Saved registers (12 registers)
;;;   f10-f17 aka fa0-fa7: FP function argument, where f10 and f11 are return value (8 registers)
;;;  Alignment:
;;;   ??? RISCV
;;;   double-floats & 64-bit integers are 8-byte aligned in structs
;;;   double-floats & 64-bit integers are 8-byte aligned on the stack
;;;   stack must be 8-byte aligned at call boundaries (otherwise 4-byte)
;;;  Parameter passing:
;;;   ??? RISCV
;;;   8- and 16-bit integer arguments zero- or sign-extended to 32-bits
;;;   32-bit integer arguments passed in a1-a4, then on stack
;;;   64-bit integer arguments passed in a1 or a3, then on stack
;;;       little-endian: a1 (a3) holds lsw, a2 (a4) holds msw
;;;       big-endian: a1 (a3) holds msw, a2 (a4) holds lsw
;;;   8- and 16-bit integer return value zero- or sign-extended to 32-bits
;;;   32-bit integer return value returned in r0 (aka a1)
;;;   64-bit integer return value passed in r0 & r1 (aka a1 & a2)
;;;       little-endian: r0 holds lsw, r1 holds msw
;;;       big-endian: r0 holds msw, r1 holds lsw
;;;   single-floats passed in s0-s15
;;;   double-floats passed in d0-d7 (overlapping single)
;;;   float return value returned in s0 or d0
;;;   must allocate to a single-float reg if it's passed by for double-float alignment
;;;     (e.g., single, double, single => s0, d1, s1)
;;;   ... unless a double has been stack-allocated
;;;     (e.g., 15 singles, double => s0-s14, stack, stack)
;;;   stack grows downwards.  first stack args passed at lowest new frame address.
;;;   return address passed in LR

;; Mapping of scheme specific task registers to registers of the CPU
(define-registers
  (reserved
    ;; Three or more cols for each definition
    ;reg   alias ...         callee-save reg-mdinfo
    [%tc   %x9 %s1           #t          9 uptr] ;; thread context
    [%sfp  %x8 %s0  %fp      #t          8 uptr] ;; scheme frame pointer
    [%ap   %x10 %a0 %Carg1 %Cretval   #f         10 uptr] ;;  
    [%trap %x11 %a1 %Carg2 %Cretval1  #f         11 uptr] ;; tracks when scheme should check for interrupts
    [%real-zero %x0          #f          0 uptr]);; hardwired zero - can't call it %zero
  (allocable
    [%ac0  %x12 %a2 %Carg3   #f         12 uptr] ;; argument count
    [%xp   %x13 %a3 %Carg4   #f         13 uptr] ;; used during alloc for the computed alloc spot
    [%ts   %x14 %a4 %Carg5   #f         14 uptr] ;; special temps
    [%td   %x15 %a5 %Carg6   #f         15 uptr] ;; special temps
    [%cp   %x16 %a6 %Carg7   #f         16 uptr] ;; closure pointer
    ;; Extra registers - length should match asm-arg-reg-max
    [      %x1  %ra %lr               #f  1 uptr]
    [      %x3  %gp                   #f  3 uptr]
    [      %x4  %tp                   #f  4 uptr]
    [      %x5  %t0                   #f  5 uptr]
    [      %x6  %t1                   #f  6 uptr]
    [      %x7  %t2                   #f  7 uptr]
    [      %x17 %a7 %Carg8            #f 17 uptr]
    [      %x18 %s2                   #t 18 uptr]
    [      %x19 %s3                   #t 19 uptr]
    [      %x20 %s4                   #t 20 uptr]
    [      %x21 %s5                   #t 21 uptr]
    [      %x22 %s6                   #t 22 uptr]
    [      %x23 %s7                   #t 23 uptr]
    [      %x24 %s8                   #t 24 uptr]
    [      %x25 %s9                   #t 25 uptr]
    [      %x26 %s10                  #t 26 uptr]
    [      %x27 %s11                  #t 27 uptr]
    [      %x28 %t3                   #f 28 uptr]
    [      %x29 %t4                   #f 29 uptr]
    [      %x30 %t5                   #f 30 uptr]
    [      %x31 %t6                   #f 31 uptr]
    [                     %f18 %fs2    #t 51 fp]
    [                     %f19 %fs3    #t 52 fp]
    )
  (machine-dependent
   [%sp                  %x2          #t  2 uptr]
   ;; There is really not a specific number for the pc reg
   ;; so we fake it and call it 32
   [%pc                               #f 32 uptr]
   ;; Floating point registers
   [                     %f0  %ft0    #f 33 fp]
   [                     %f1  %ft1    #f 34 fp]
   [                     %f2  %ft2    #f 35 fp]
   [                     %f3  %ft3    #f 36 fp]
   [                     %f4  %ft4    #f 37 fp]
   [                     %f5  %ft5    #f 38 fp]
   [                     %f6  %ft6    #f 39 fp]
   [                     %f7  %ft7    #f 40 fp]
   [                     %f8  %fs0    #t 41 fp]
   [                     %f9  %fs1    #t 42 fp]
   [%Cfparg1 %Cfpretval  %f10 %fa0    #f 43 fp]
   [%Cfparg2 %Cfpretval1 %f11 %fa1    #f 44 fp]
   [%Cfparg3             %f12 %fa2    #f 45 fp]
   [%Cfparg4             %f13 %fa3    #f 46 fp]
   [%Cfparg5             %f14 %fa4    #f 47 fp]
   [%Cfparg6             %f15 %fa5    #f 48 fp]
   [%Cfparg7             %f16 %fa6    #f 49 fp]
   [%Cfparg8             %f17 %fa7    #f 50 fp]
   ;; f18 and f19 are in the allocable section
   [                     %f20 %fs4    #t 53 fp]
   [                     %f21 %fs5    #t 54 fp]
   [                     %f22 %fs6    #t 55 fp]
   [                     %f23 %fs7    #t 56 fp]
   [                     %f24 %fs8    #t 57 fp]
   [                     %f25 %fs9    #t 58 fp]
   [                     %f26 %fs10   #t 59 fp]
   [                     %f27 %fs11   #t 60 fp]
   [                     %f28 %ft8    #f 61 fp]
   [                     %f29 %ft9    #f 62 fp]
   [                     %f30 %ft10   #f 63 fp]
   [                     %f31 %ft11   #f 64 fp]
   ))

;;; SECTION 2: instructions
(module (md-handle-jump) ; also sets primitive handlers

    (import asm-module)
  
  (define mem?
    (lambda (x) #t))
  
  (define md-handle-jump
    (lambda (t)
      (with-output-language
       (L15d Tail)
       (define long-form
         (lambda (e)
           (let ([tmp (make-tmp 'utmp)])
             (values
              (in-context Effect `(set! ,(make-live-info) ,tmp ,e))
              `(jump ,tmp)))))
       
       (nanopass-case (L15c Triv) t
                      [,lvalue (values '() `(jump ,lvalue))]
                      [(literal ,info) (values '() `(jump (literal ,info)))]
                      [(label-ref ,l ,offset) (values '() `(jump (label-ref ,l ,offset)))]
                      [else (long-form t)])))))

;;; SECTION 3: assembler
(module asm-module (asm-foreign-call
                    asm-foreign-callable
                    asm-enter)
  
  (module (asm-foreign-call
           asm-foreign-callable
           asm-enter)
      
      (define-who asm-foreign-call
        (with-output-language
         (L13 Effect)
         (let () #false)))
    
    (define-who asm-foreign-callable
      (with-output-language
       (L13 Effect)
       (let () #false)))
    
    (define asm-enter values)))
