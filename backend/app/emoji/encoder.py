"""multilingual-e5-small on onnxruntime: text → unit vector of 384 floats."""

from pathlib import Path

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

MODEL_FILE = "model_quantized.onnx"
TOKENIZER_FILE = "sentencepiece.bpe.model"

# XLM-R vocabulary: four special tokens, then the sentencepiece pieces shifted by one
# (sentencepiece's own id 0 is its <unk>).
BOS, PAD, EOS, UNK = 0, 1, 2, 3
# Titles and descriptions are short; a longer text is cut rather than refused.
MAX_TOKENS = 128


class Encoder:
    def __init__(self, model_dir: Path, threads: int = 1):
        # sentencepiece rather than the HF tokenizer.json: the same ids for ~70 MB of memory
        # instead of ~230 (the 250k-token vocabulary parsed from JSON).
        self.sp = spm.SentencePieceProcessor(model_file=str(model_dir / TOKENIZER_FILE))
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        opts.inter_op_num_threads = 1
        opts.enable_cpu_mem_arena = False
        self.session = ort.InferenceSession(
            str(model_dir / MODEL_FILE), opts, providers=["CPUExecutionProvider"]
        )

    def ids(self, text: str) -> list[int]:
        pieces = self.sp.encode(text)[: MAX_TOKENS - 2]
        return [BOS, *(i + 1 if i else UNK for i in pieces), EOS]

    def encode(self, texts: list[str], batch: int = 32) -> np.ndarray:
        out = []
        for start in range(0, len(texts), batch):
            rows = [self.ids(t) for t in texts[start : start + batch]]
            ids = np.full((len(rows), max(map(len, rows))), PAD, dtype=np.int64)
            mask = np.zeros_like(ids)
            for r, row in enumerate(rows):
                ids[r, : len(row)] = row
                mask[r, : len(row)] = 1
            feed = {"input_ids": ids, "attention_mask": mask, "token_type_ids": np.zeros_like(ids)}
            hidden = self.session.run(["last_hidden_state"], feed)[0]
            # Mean over the real tokens, then unit length: cosine similarity is a dot product.
            weights = mask[..., None].astype(np.float32)
            vectors = (hidden * weights).sum(axis=1) / weights.sum(axis=1)
            out.append(vectors / np.linalg.norm(vectors, axis=1, keepdims=True))
        return np.concatenate(out).astype(np.float32)
