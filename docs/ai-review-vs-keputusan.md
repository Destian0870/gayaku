# AI review findings against the final decisions

The codelab asks for a table of what the AI proposed, what was accepted, and what was rejected with
a reason. This file records the findings from the model-work thread (2026-10-22 → 2026-11-03), each
with the evidence that decided it. Two entries below were **rejected**, and one was rejected because
the AI's claim was simply wrong - it is kept here on purpose.

| # | AI proposal | Decision | Evidence |
| --- | --- | --- | --- |
| 1 | Merge the two training sources instead of swapping to the new one | **Accepted** | Swapping leaves no `Shoes`/`Hat` class, so the scanner stops recognising shoes. Merge is recorded in `docs/adr/0008`. |
| 2 | Deduplicate by content before splitting; 1,401 photographs are the same picture resized | **Accepted** | Measured: 1,412 shared basenames, 1,401 with a 16×16 signature distance ≤ 3. `merge_datasets.py` groups by sha256, shared basename and dHash. |
| 3 | "No `phash` may appear in more than one split" enforced as exact hash equality | **Rejected** | Eleven different plain-background photographs share `0x0707070707070707` while sitting 14–25 grey levels apart, so equality-only refuses a correct merge. The check compares the 16×16 signature before calling a leak, and records the 7 surviving collisions in `merged_dataset.json`. |
| 4 | "`Sweter` and `Kaos_Lengan_Panjang` share a Category, so the label conflict cannot change the outfit" | **Rejected - the AI claim was wrong** | `labels.json` says `Longsleeve` is Tops and `Sweter` is **Outerwear**, so the 403 photographs the default refiles move to another wardrobe tab. Corrected in `5c24e36` (ADR-0008 and the script's decisions text) and in the README by `fb831a6`. |
| 5 | Keep `Kaos_Lengan_Panjang` as a class at 172 photographs | **Accepted, then qualified** | A spot check of five surviving photographs found three knitted sweaters or cardigans, so the class is mixed and its recall is the number to read. Recorded as a consequence in ADR-0008 (`33b0bfc`) after training measured 33.3 % recall on it. |
| 6 | Compute per-class precision/recall with scikit-learn | **Rejected** | It loads a second OpenMP runtime on this Windows interpreter and aborts the run with `OMP: Error #15` before the checkpoint is written. The metrics are derived from Ultralytics' own confusion matrix instead, which reproduced the same accuracy to 1e-6 (`train_local.py`). |
| 7 | Export `.tflite` with `onnx2tf` in the repository's Python 3.14 environment | **Rejected by measurement** | `onnx2tf` fails on a two-node Gemm/Softmax model in that environment (`Conversion error analysis: ValueError`), so the conversion moved to an isolated Python 3.12 environment built with `uv` (`9b0e8ae`). Verified on the real export: `[1,224,224,3]` float32 in, `[1,18]` float32 out, scores sum 1.000000. |
| 8 | Detection was out of scope for v1 (ADR-0005) | **Rejected by the product owner** | The owner's reason for choosing YOLO was multi-garment photos. ADR-0009 supersedes ADR-0005: a detector answers *where* and a coarse Category, and the 18-class classifier names each crop. |
| 9 | Fashionpedia as the first box-annotated source | **Accepted** | Annotations CC BY 4.0, 46,781 photographs, 342,182 boxes, and its categories cover `shoe` and `hat`. Its 19 garment-*part* categories must be dropped, which `fashionpedia_to_yolo.py` does and reports. |

## What the AI got wrong, and how it was caught

Entry 4 is the one worth remembering: the claim looked reasonable, matched the owner's own summary,
and was still false against the file that defines the mapping. It was caught by re-reading
`labels.json` rather than trusting the prose, and the correction changed a consequence in an ADR
plus a user-visible behaviour (which wardrobe tab 403 photographs land in).

Entry 3 is the opposite case: a literal instruction that would have made a correct merge fail. It
was rejected only after reproducing the collision, not because it sounded inconvenient.

## Rules this file is meant to enforce

* A finding is accepted only with evidence that can be re-run: a command, a test, or a measurement.
* A finding that contradicts a file in the repository is settled by the file, not by the summary.
* Style preferences belong to `dart format` and CI, not to review comments.
