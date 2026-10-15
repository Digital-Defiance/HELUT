# HELUT and the Esbjerg bombe

Jessica Mulein, 7 October 2026. For Christoffer Duif.
Read from `P1030680-crib-search-code.zip`, the V5 README, and
`cribs-tried-P1030680.xlsx` (About sheet dated 4 October 2026).
The kernel was not run. No new menu was started.

## The machines are already searching the same grid

One full crib, as the README defines it, is

336 wheel orders × Beta/Gamma × 26 Greek offsets × thin B/C
× 17,576 window positions × 26 right-ring settings
= 1.597×10^10 states.

That is the same count as a HELUT right-ring placement:
336 orders × 2 Greek × 2 thin reflectors × 26 right rings × a 26^4 lane
grid. The Greek offset sits in your unit list and in our lane index.
Both programs pin the left ring at A. Both fold the still Greek wheel
into the thin reflector.

Inside each thread your kernel also loops the 26 middle rings. Every
version in the archive does (V1, V3, V4, V5). A ring whose window never
steps the left wheel is the same machine as any other such ring, and
one of them is tested. Every ring that does step it is tested. So one
full crib covers every middle and right ring. That is what
`helut --welchman --bombe-ring-sweep --bombe-middle-ring` covers, not
the right-ring catalog alone. The first version of this note said your
GPU did not enumerate the middle ring. That was wrong.

The kernel is WebGPU (WGSL) through Dawn: RTX 5070 on D3D12, RTX 5090
on Vulkan, and, as of 7 October 2026, this Mac's GPU through Dawn's
Metal backend. The V5 pipeline compiled. Workgroup memory is 30,704
bytes and the limit here is 32,768.

On an RTX 5070, V5 is 588 units/s for a 26-letter crib and 3,124 for an
18-letter crib. On this M4 Max, the same bench (warmup, then 1,500
units from unit 12,000) measured 502 and 1,996. HELUT on the same cribs
and the same chip, middle ring pinned at A, is 192 and 219 shells/s.
A shell and a unit are the same quoted count. The unit also walks the
middle ring, so the timed HELUT crib is the smaller search. A full
right-ring crib here took 182 s and 160 s (`logs/duif-bench-full.log`).

## What is different, apart from deletions and in-menu garbles

**Loop test, before the 26 stecker seeds.** As of 7 October 2026 the
Metal kernel does this on the exact board. A seed is propagated only
when it is a fixed point of the closed walks through the test letter
(`TuringMenuWalks`, at most eight shortest walks), and the kernel
follows four seeds along each walk. On a 1,500-shell sample that is
about 2× from the loop test and another 8% from the four seeds.
Tolerance above 0 skips the filter, because a dropped edge can remove
the walk. `TuringLoopTests` checks that a seed the host board accepts
still passes the walks, and that the GPU stops match the host board
with the four-wide test on and off. The popcount cache from V5 was not
ported. It needs one thread to walk the rings, and this kernel is one
thread per window position.

The step table was ported and then switched off. On the 26-letter crib
it was slower than the notch walk (175 shells/s against 191). On the
67-step span it was about 3% faster, and only together with the four
seeds. The sweep leaves it off. The stops matched either way.

The cache is exact. Each step mask is a tail, every position from the
first step on, so its intersection with the walk positions is the last
n of them, and n is the popcount. We checked the key on the step rule
from your table: single-notch and Z/M notch layouts, all 676 middle and
right starts, 400 random walk sets each, 1,081,600 lookups, no key with
two different step patterns on the walk. The 7 October reply said the
cache could reuse the wrong mask. That was wrong. It was not ported
because it pays off inside your thread layout, one thread walking the
rings for a fixed offset. Our kernel runs one thread per window
position for one ring setting.

**Middle ring.** The catalog pins it at A. That is exact only while the
middle wheel does not turn over inside the crib. Sweeping it here costs
about 6.5–11×, not 26×, and that sweep has been done for 24 strong
menus under a 42-order prior, not for the whole catalog. Your kernel
covers it on every crib: the GPU loops all 26 middle rings, and the CPU
recovers which ring produced a stop from the step mask
(`maskerPasser`). On a shared placement, your negative covers the
middle ring and ours does not.

**Wheel orders on the tail of our catalog.** Cribs of at least 16
letters, right ring swept, middle ring A:

- 417 menus, all 336 orders. Log `logs/campaign-catalog-rings.log`,
  last completed index 417.
- 451 menus, 42 of 336 orders (VIII on the fast wheel). Log
  `logs/campaign-catalog-rings-viii-fast.log`, 451/451, no break.
  Best physical score IC 0.041, tail −4.488.

Your “full M4” row is all 336. On a shared string that we ran only in
the second list, your negative is the wider wheel-order statement.

**How much of the crib is inside the bombe.** Your GPU window is at
most 26 letters, chosen as the strongest window. The rest of a longer
crib is checked on the CPU, and exactly one equation may be dropped,
only outside that window. A wrong letter inside the window hides the
key unless that letter is masked and the crib is run again. HELUT puts
up to 40 edges in the menu itself. A longer crib is a stronger board
on our side. A shorter slice is a different hypothesis, not a rerun of
the longer one.

**What counts as a hit.** You keep a stop with at most one crib miss
and a trigram score above −660, on a model built from the decrypted
U-534 corpus. Real texts in your note score about −468 to −568; false
candidates top out near −633. Our break bar is an exact crib, index of
coincidence at least 0.055, log-likelihood tail above −3.600, and at
most ten plugs. A candidate can pass one bar and fail the other. The
catalog negative is “dead at the board” or a physical score under that
bar. It is not a trigram hillclimb. The hillclimb of the unforced
plugs (six rounds, cap ten pairs) is yours. Our later plug climber is
a separate stage and was not what produced the catalog negatives.

**Letter 68.** Your `u534.txt` has L. Our fixtures have C
(`…KQNGSCHVGF`). You always skip the position. Nineteen shared
placements span it, so those menus are not the same equations. They
are listed at the end. We have not decided which letter is right. On
the 800 × 1153 photograph, row 19 ends in a tall looped stroke of the
same height and shape as the final `l` of `VROL` (row 1) and `VAOL`
(row 21). 54 of our 417 full-order menus and 50 of the 450 VIII-fast
menus have an edge there, and those negatives assume C. Neither letter
changes which placements of at least 16 letters are legal.

**Cribs under 16 letters.** We drop them. A 14-letter crib has already
produced a false positive under the old bar. You run them. 347 of the
2,346 slots have fewer than 16 known letters. We are not going to run
those.

**Deletions, and a garble inside the window.** Your setup does not
model a missing group. HELUT does, by splicing the crib, and that arm
is only partly run. Your About sheet says a ruled-out row still misses
one garbled letter inside the menu, or a different spelling. Our
tolerant board drops menu edges and has been shown, on a known key, to
keep a setting the exact board loses. That is the real complement.
It is not a reason to repeat an exact string that both programs have
already rejected.

## What has already been run twice

Of 2,346 position slots in the spreadsheet:

| | slots |
|---|---:|
| Same string, same offset, as a catalog menu in the logs | 221 |
| of which only the 42-order run | 192 |
| of which the 336-order run | 29 |
| of which those 29, also in the 24-menu middle-ring sweep | 5 |
| Shorter slice of a longer catalog menu we already ran | 186 |
| Not in the logged catalog menus | 1,939 |
| of those, at least 16 known letters and marked ruled out | 1,652 |
| of those, unfinished | 37 |
| of those, older solver (“some doubt”) | 6 |

The whole sheet, including the rows that do overlap, marks 2,299 ruled
out, 38 unfinished, and 9 older-solver. One unfinished slot and three
older-solver slots sit inside the 407 overlapping placements.

638 of the catalog menus we logged do not appear on your sheet as the
same string and offset. They are overlapping slices of about 100
phrases taken from the broken U-534 decrypts, kept only when the phrase
occurs in at least two messages. Your 1,939 absent slots are mostly
outside that filter: time groups (`ABEINS…`), sailing reports
(`ABGELEGTZURPROBEFAHRT`), and other openings. Your negative on those
stands as yours. We have not repeated it, and we are not importing the
list into the catalog.

## What we should not repeat

The 221 exact matches. Running them again on our 42-order prior adds
no wheel order your full-M4 row already claims, and your rows also
cover the middle ring, which ours pinned at A. Running all 336 orders
again here duplicates a search we have not replayed bit for bit.

The 186 shorter slices. Our longer menu is the stronger exact test of
the longer hypothesis. Your shorter menu is fewer letters. Both
negatives can stand. Neither needs to be run a second time as the same
hypothesis.

The 38 unfinished rows and the 9 older-solver rows. Those are yours to
rerun, on the current kernel, if you still want them. They are not a
HELUT gap.

The 1,652 ruled-out placements of at least 16 letters that we never
ran. Importing them would test hypotheses our recurrence filter
excluded. Your sheet already records the exact-letter negative, with
the garble caveat you wrote.

## What is actually still open

A garbled letter inside the bombe window, for a crib we have a
historical reason to trust. Not for all 2,299 ruled-out rows.

A missing group. That is the indel arm. It is not in your kernel. The
form gives no sign of one: 22 rows are filled (`VROL NMKA`, 18 text
groups, `VAOL NMKA`), and the Gruppenzahl box reads 22, faint under the
stain. 18 groups is 72 letters.

The middle ring and the other 294 wheel orders, on the 451 menus we
ran only with VIII fast. You offered on 7 October to run that list at
all 336 orders and every ring setting. 21 of the 450 distinct menus have
no loop, so the loop test will not help there, and those are the ones
most likely to hit your stop limit.

Letter 68, C or L, on any crib that uses that position.

## The nineteen shared placements that span letter 68

All marked ruled out. “42” means we ran them only with VIII on the
fast wheel. “336” means all wheel orders. You skipped the letter in
every case.

| orders | offset | crib |
|---:|---:|---|
| 42 | 55 | KOMXADMXUUUBOOTE |
| 42 | 56 | KOMXADMXUUUBOOTE |
| 42 | 53 | KOMXADMXUUUBOOTEY |
| 42 | 55 | KOMXADMXUUUBOOTEY |
| 42 | 50 | KOMXADMXUUUBOOTEYF |
| 42 | 53 | KOMXADMXUUUBOOTEYF |
| 42 | 51 | TTTFFFEINSSIBENXX |
| 42 | 52 | TTTFFFEINSSIBENXX |
| 42 | 53 | TTTFFFEINSSIBENXX |
| 42 | 54 | TTTFFFEINSSIBENXX |
| 42 | 55 | TTTFFFEINSSIBENXX |
| 336 | 40 | UUUEINSEINSNULDREIKKEISELEKKXX |
| 42 | 49 | UUUFUNFDREIVIERKKNO |
| 42 | 52 | UUUFUNFDREIVIERKKNO |
| 42 | 53 | UUUFUNFDREIVIERKKNO |
| 42 | 49 | UUUZWODREISECHSFUNF |
| 42 | 54 | XUUUFLOTTXVVVUUU |
| 42 | 56 | XUUUFLOTTXVVVUUU |
| 42 | 52 | ZWODREISECHSEINS |
