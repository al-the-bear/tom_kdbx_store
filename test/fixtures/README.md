# Test fixtures

`tom_kdbx_written.kdbx` was written by `tom_kdbx` 2.4.2+tom.4, the KDBX
library this package used before `tom_kpasslib`: KDBX 4.0, Argon2d, AES-256.
Password `interop`. One entry: title `interop title`, protected password
`interop secret`, a field `Note` with `unicode ✓ äöü`, an attachment `a.txt`
holding `attached bytes`; the meta custom data `k` = `v`.

It is the same file as `tom_kpasslib`'s `test/fixtures/interop/tom_kdbx_argon2d_aes.kdbx`,
made by the generator in the Tom workspace's quest folder
(`_ai/quests/tom_core/ideas/tom_secrets_manager/kdbx_interop_fixtures/`).
