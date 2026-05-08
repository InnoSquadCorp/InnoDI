# InnoDI performance history

This branch is an append-only time series for macro-performance
measurements. Entries land here from `Tools/append-performance-history.sh`
running on each push to `main`. Do not commit application code or
documentation here; `Tools/check-performance-trend.sh` reads only the
files under `history/`.
