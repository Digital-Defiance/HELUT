#!/usr/bin/env python3
"""Classical Enigma defects on the byte-local walk and on the wide rotor patch.

The byte-local arm is the mirrored center. It must still show the defects.
The wide arm is the E256-W rotor stack at 4 rounds, candidate mode.
This does not select a cipher and does not move a claim.
"""

from __future__ import annotations

import numpy as np

import e256_wide_gate as wide

INV_MIX = (
    (0x0E, 0x0B, 0x0D, 0x09),
    (0x09, 0x0E, 0x0B, 0x0D),
    (0x0D, 0x09, 0x0E, 0x0B),
    (0x0B, 0x0D, 0x09, 0x0E),
)
ROUNDS = 4


def mirrored(value: int, forward: np.ndarray, inverse: np.ndarray, mask: int) -> int:
    return int(inverse[int(forward[value]) ^ mask])


def two_cycles(table: list[int]) -> int:
    seen = [False] * 256
    pairs = 0
    for start in range(256):
        if seen[start]:
            continue
        nxt = table[start]
        if table[nxt] != start or nxt == start:
            return -1
        seen[start] = True
        seen[nxt] = True
        pairs += 1
    return pairs


def material(namespace: wide.RotorNamespace, seed: bytes, mask_byte: int) -> wide.RoundMaterial:
    rotor_ids = np.frombuffer(wide.hashlib.sha512(b"rotors" + seed).digest() * 6, dtype=np.uint8)[: 12 * 32].copy()
    raw = wide.hashlib.sha512(b"masks" + seed).digest()
    masks = np.frombuffer(raw * 13, dtype=np.uint8)[: 13 * 32].copy()
    masks[0] = mask_byte
    return wide.RoundMaterial(context=seed, rotor_ids=rotor_ids.reshape(12, 32), masks=masks.reshape(13, 32))


def wide_encrypt(namespace: wide.RotorNamespace, state: bytes, item: wide.RoundMaterial) -> bytes:
    return wide.permute(state, namespace, item, ROUNDS, mode="candidate")


def wide_decrypt(namespace: wide.RotorNamespace, state: bytes, item: wide.RoundMaterial) -> bytes:
    return wide.inverse_permute(
        state, namespace, item, ROUNDS, mode="candidate", inverse_mix_matrix=INV_MIX
    )


def main() -> None:
    wide.initialize_primitives()
    namespace = wide.RotorNamespace(wide.extract_prk(wide.test_ikm(0)))
    forward = namespace.forward[0]
    inverse = namespace.inverse[0]

    involution_masks = 0
    identity_at_zero = mirrored(0, forward, inverse, 0) == 0 and all(
        mirrored(value, forward, inverse, 0) == value for value in range(256)
    )
    for mask in range(1, 256):
        table = [mirrored(value, forward, inverse, mask) for value in range(256)]
        if two_cycles(table) == 128:
            involution_masks += 1
    print(f"byte-local mask 0 is identity: {identity_at_zero}")
    print(f"byte-local nonzero masks that are 128 two-cycles: {involution_masks}/255")

    item = material(namespace, b"defect-patch-v1", 0x3C)
    plain = bytes(range(32))
    cipher = wide_encrypt(namespace, plain, item)
    if wide_decrypt(namespace, cipher, item) != plain:
        raise SystemExit("ABORT — wide rotor round trip failed")
    twice = wide_encrypt(namespace, cipher, item)
    print(f"wide encrypt-twice equals plaintext: {twice == plain}")

    same = 0
    samples = 0
    isolated = 0
    for index in range(32):
        seed = wide.u16be(index)
        block = wide.hashlib.sha256(b"plain" + seed).digest()
        current = material(namespace, b"block" + seed, 0x11)
        out = wide_encrypt(namespace, block, current)
        same += sum(left == right for left, right in zip(block, out))
        samples += 32
        flipped = bytearray(block)
        flipped[0] ^= 0x01
        other = wide_encrypt(namespace, bytes(flipped), current)
        if sum(left != right for left, right in zip(out, other)) == 1:
            isolated += 1
    print(f"wide ciphertext byte equals plaintext byte: {same}/{samples}")
    print(f"wide one-byte flips that change only one output byte: {isolated}/32")

    left = material(namespace, b"related", 0x01)
    right_masks = left.masks.copy()
    right_masks[1, 0] ^= 0x01
    right = wide.RoundMaterial(context=b"related-b", rotor_ids=left.rotor_ids, masks=right_masks)
    quotient_involutions = 0
    for lane in range(32):
        table = []
        for value in range(256):
            block = bytearray(32)
            block[lane] = value
            first = wide_encrypt(namespace, bytes(block), left)
            second = wide_decrypt(namespace, first, right)
            table.append(second[lane])
        if two_cycles(table) == 128:
            quotient_involutions += 1
    print(f"wide related-mask lanes that stay 128 two-cycles: {quotient_involutions}/32")

    recovered = 0
    for lane in range(32):
        block = bytearray(32)
        block[lane] = 0x5A
        image = wide_encrypt(namespace, bytes(block), left)[lane]
        guess = int(forward[0x5A]) ^ int(forward[image])
        other = bytearray(32)
        other[lane] = 0xA5
        predicted = mirrored(0xA5, forward, inverse, guess)
        actual = wide_encrypt(namespace, bytes(other), left)[lane]
        if predicted == actual:
            recovered += 1
    print(f"wide lanes where one pair recovers the byte map: {recovered}/32")

    def quotient(block: bytes, other: wide.RoundMaterial) -> bytes:
        return wide_decrypt(namespace, wide_encrypt(namespace, block, left), other)

    reselected = left.rotor_ids.copy()
    reselected[0, 0] ^= 0x01
    rotor_change = wide.RoundMaterial(context=b"rotor-change", rotor_ids=reselected, masks=left.masks.copy())
    mask_hits = 0
    rotor_hits = 0
    for index in range(16):
        block = wide.hashlib.sha256(b"quotient" + bytes([index])).digest()
        mask_hits += quotient(quotient(block, right), right) == block
        rotor_hits += quotient(quotient(block, rotor_change), rotor_change) == block
    print(f"wide mask-only quotient involutions: {mask_hits}/16")
    print(f"wide rotor-reselect quotient involutions: {rotor_hits}/16")
    if mask_hits != 16 or rotor_hits != 0:
        raise SystemExit("ABORT — related-position quotient changed")


if __name__ == "__main__":
    main()
