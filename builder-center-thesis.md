# Thesis: Why Retry Isn't Recovery

When an autonomous worker fails, the natural instinct is to retry. But retry is not recovery. Retry assumes the same conditions will yield the same result. In cross-chain context, conditions shift between chains, proofs expire, and state changes on one side invalidate assumptions on the other.

True recovery requires the worker to re-engage with verified state—establishing new evidence, re-evaluating policy, and deriving fresh capability. Blind retry risks operating on stale authority, potentially exceeding the verified bounds that the system designed to enforce.

ATLAS makes the worker responsible for getting the job to a verified outcome, within the authority it was given. If the verified state has changed, the capability is no longer valid. Recovery means re-proving, not re-sending.