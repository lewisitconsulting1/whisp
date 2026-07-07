#!/usr/bin/env python3
"""STT benchmark: parakeet-mlx vs mlx-whisper vs whisper.cpp on M-series.

Measures per-utterance wall-clock transcription time (model resident = warm)
plus one cold model-load time per engine, and WER against ground truth.
Run engines sequentially, nothing else heavy on the machine.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

import jiwer

HERE = Path(__file__).parent
AUDIO = HERE / "audio"
MODELS = HERE / "models"
RESULTS = HERE / "results"

GT = json.load(open(AUDIO / "ground_truth.json"))
SAMPLES = {
    "short": AUDIO / "short.wav",
    "medium": AUDIO / "medium.wav",
    "long": AUDIO / "long.wav",
    "medium_uk": AUDIO / "medium_uk.wav",
}
GT["medium_uk"] = GT["medium"]
WARM_RUNS = 3

norm = jiwer.Compose([
    jiwer.ToLowerCase(),
    jiwer.RemovePunctuation(),
    jiwer.RemoveMultipleSpaces(),
    jiwer.Strip(),
    jiwer.ReduceToListOfListOfWords(),
])


def wer(ref: str, hyp: str) -> float:
    return jiwer.wer(ref, hyp, reference_transform=norm, hypothesis_transform=norm)


def bench_parakeet():
    from parakeet_mlx import from_pretrained

    out = {"engine": "parakeet-mlx", "model": "mlx-community/parakeet-tdt-0.6b-v3"}
    t0 = time.perf_counter()
    model = from_pretrained(out["model"])
    out["load_s"] = round(time.perf_counter() - t0, 3)
    runs = {}
    for name, wav in SAMPLES.items():
        model.transcribe(str(wav))  # warmup
        times, text = [], ""
        for _ in range(WARM_RUNS):
            t0 = time.perf_counter()
            text = model.transcribe(str(wav)).text
            times.append(time.perf_counter() - t0)
        runs[name] = {
            "warm_s": round(min(times), 3),
            "wer": round(wer(GT[name], text), 4),
            "text": text.strip(),
        }
    out["runs"] = runs
    return out


def bench_mlx_whisper(repo: str):
    import mlx_whisper

    out = {"engine": "mlx-whisper", "model": repo}
    t0 = time.perf_counter()
    mlx_whisper.transcribe(str(SAMPLES["short"]), path_or_hf_repo=repo)  # loads+caches model
    out["load_s"] = round(time.perf_counter() - t0, 3)  # includes one transcription
    runs = {}
    for name, wav in SAMPLES.items():
        times, text = [], ""
        for _ in range(WARM_RUNS):
            t0 = time.perf_counter()
            text = mlx_whisper.transcribe(str(wav), path_or_hf_repo=repo, language="en")["text"]
            times.append(time.perf_counter() - t0)
        runs[name] = {
            "warm_s": round(min(times), 3),
            "wer": round(wer(GT[name], text), 4),
            "text": text.strip(),
        }
    out["runs"] = runs
    return out


def bench_whisper_cpp(model_file: str, label: str):
    """whisper-cli spawns a fresh process per call (worst case: includes model load)."""
    mpath = MODELS / model_file
    out = {"engine": "whisper.cpp", "model": label, "note": "per-call time includes process spawn + model load (CLI mode)"}
    runs = {}
    for name, wav in SAMPLES.items():
        times, text = [], ""
        for _ in range(WARM_RUNS):
            t0 = time.perf_counter()
            r = subprocess.run(
                ["whisper-cli", "-m", str(mpath), "-f", str(wav), "-nt", "-l", "en", "--no-prints"],
                capture_output=True, text=True, check=True,
            )
            times.append(time.perf_counter() - t0)
            text = r.stdout
        runs[name] = {
            "warm_s": round(min(times), 3),
            "wer": round(wer(GT[name], text), 4),
            "text": text.strip(),
        }
    out["runs"] = runs
    return out


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    results = []
    jobs = {
        "parakeet": lambda: bench_parakeet(),
        "mlx-large": lambda: bench_mlx_whisper("mlx-community/whisper-large-v3-turbo"),
        "cpp-base": lambda: bench_whisper_cpp("ggml-base.en.bin", "whisper.cpp base.en"),
        "cpp-large": lambda: bench_whisper_cpp("ggml-large-v3-turbo.bin", "whisper.cpp large-v3-turbo"),
    }
    for key, fn in jobs.items():
        if which not in ("all", key):
            continue
        print(f"=== {key} ===", flush=True)
        try:
            r = fn()
            results.append(r)
            for name, run in r["runs"].items():
                print(f"  {name:10s} {run['warm_s']:.3f}s  WER {run['wer']:.1%}", flush=True)
        except Exception as e:
            results.append({"engine": key, "error": str(e)})
            print(f"  FAILED: {e}", flush=True)
    RESULTS.mkdir(exist_ok=True)
    path = RESULTS / f"stt_{which}.json"
    json.dump(results, open(path, "w"), indent=2)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
