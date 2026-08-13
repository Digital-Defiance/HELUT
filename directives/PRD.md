# HELUT PRD: Phase 1 (The Negacyclic Matrix Kernel)

## Objective
Prove that Apple Silicon's `MPSGraph` can evaluate exact TFHE polynomial multiplication by executing dense matrix-vector multiplications on `UInt32` tensors, relying on native integer overflow for modulo $2^{32}$ reduction.

## The Mathematical Mapping
TFHE Blind Rotation relies on multiplying a Test Polynomial (the Accumulator) by Bootstrapping Key polynomials. 
Instead of NTT, we will use a **Negacyclic Toeplitz Matrix**.
Given a polynomial $A$ of degree $N$, its negacyclic matrix representation $M_A$ is an $N \times N$ matrix where:
- The first column is $(a_0, a_1, \dots, a_{N-1})^T$
- Each subsequent column is the previous column shifted down by 1, with the element wrapping to the top negated.
- Multiplying $M_A \cdot X$ (where $X$ is the accumulator vector) evaluates exactly to $A * X \pmod{X^N+1}$.

## Implementation Plan
1. **CPU Oracle (Rust or Swift):** Write a simple, unoptimized schoolbook polynomial multiplier for $\mathbb{Z}_{2^{32}}[X]/(X^N+1)$. This is our correctness gate.
2. **Matrix Expansion (Host):** Write a function that takes a random polynomial $A$ (size $N=1024$) and expands it into the $1024 \times 1024$ Negacyclic Toeplitz matrix $M_A$ of `UInt32`. Because negative numbers wrap in `UInt32` (e.g., $-a \equiv 2^{32}-a$), standard `UInt32` matrix math will hold the negacyclic properties automatically.
3. **MPSGraph Compute (Device):** 
   - Load $M_A$ and $X$ into `MPSGraph`.
   - Execute a dense `matrixMultiplication`.
   - Read the result back.
4. **The Gate:** Assert that the `MPSGraph` output matches the CPU Oracle output bit-for-bit.

## Constraints
- Target $N=1024$.
- Everything must be `UInt32`. The NPU/GPU must handle the modulo overflow natively.
