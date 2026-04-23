# Policy Boundaries

InnoDI は明示的な境界を置くことで検証を決定的に保ちます。

## Matching Strategy

- マクロ、Core、graph CLI は可能な限り同じ nominal-path モデルを共有
- `Outer.Container` のような nested path をサポート
- generic argument extension と `where` extension は除外
- 曖昧なケースは推測で一致させない
