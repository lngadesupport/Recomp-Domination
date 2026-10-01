"""Summarize bounded PS2_TRACE_RESOURCE_COPY logs; no gameplay/FPS claims."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

PREFIX = '[downhill:resource-copy] '
NUMERIC = ('call', 'zero_calls', 'thread', 'length', 'source', 'destination',
           'input_offset', 'output_after', 'remaining_after', 'window',
           'input_base', 'output_base', 'result')


def summarize(text: str) -> dict:
    rows, malformed = [], 0
    for line in text.splitlines():
        if PREFIX not in line:
            continue
        try:
            fields = dict(part.split('=', 1) for part in line.split(PREFIX, 1)[1].split())
            row = {key: int(fields[key]) for key in NUMERIC}
            row['source_bytes'] = fields['source_bytes']
            row['destination_bytes'] = fields['destination_bytes']
            if any(row[k] < 0 for k in NUMERIC):
                raise ValueError('negative unsigned field')
            if row['zero_calls'] > row['call'] or row['call'] == 0:
                raise ValueError('invalid counters')
            expected = min(row['length'], 16) * 2
            for key in ('source_bytes', 'destination_bytes'):
                if len(row[key]) > expected or len(row[key]) % 2:
                    raise ValueError('invalid byte sample')
                bytes.fromhex(row[key])
            rows.append(row)
        except (ValueError, KeyError):
            malformed += 1
    anomalies = []
    for index, row in enumerate(rows):
        if row['result'] != row['destination']:
            anomalies.append({'sample': index, 'kind': 'return_pointer_mismatch'})
        if row['length'] > 32 * 1024 * 1024:
            anomalies.append({'sample': index, 'kind': 'stub_size_clamp'})
        if row['length'] and not row['source_bytes']:
            anomalies.append({'sample': index, 'kind': 'source_sample_unavailable'})
        # Raw address ranges cannot prove non-overlap: guest aliases may coincide.
        # Report differing bytes as observations, not a memcpy correctness verdict.
        if row['source_bytes'] != row['destination_bytes']:
            anomalies.append({'sample': index, 'kind': 'byte_samples_differ'})
        if index and row['call'] <= rows[index - 1]['call']:
            anomalies.append({'sample': index, 'kind': 'counter_restart_or_reordering'})
    return {'samples': len(rows), 'malformed_records': malformed,
            'last_sample': rows[-1] if rows else None,
            'zero_length_samples': sum(r['length'] == 0 for r in rows),
            'observations': anomalies,
            'limits': 'Calls are sampled after 64. Zero sizes and repeated offsets alone do not prove a stall. Host clock and game FPS are not measured.'}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.log.read_text(errors='replace')), indent=2))


if __name__ == '__main__':
    main()
