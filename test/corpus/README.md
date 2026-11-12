# KDBX compatibility corpus

Files of demo data, under demo keys, written by five writers. `corpus_test.dart`
reads each with this package, compares what it reads with what KeePassXC reads
in the file, writes it back and compares again — and, with `keepassxc-cli` on
the machine, has KeePassXC read the written-back file.

## The files

`manifest.json` lists every file with its writer, KDBX version, KDF, cipher,
password and key file; the header of each is checked against it.

| Files | Written by | How |
| --- | --- | --- |
| `kp41_argon2d_aes_pw`, `kp41_argon2id_chacha20_pw`, `kp40_aeskdf_aes_keyfile`, `kp41_argon2id_aes_both`, `kp31_aeskdf_aes_pw`, `kp31_aeskdf_chacha20_both` | `tom_kpasslib` 1.1.2+tom.3 | version, KDF, cipher and key set per file |
| `tk40_argon2d_aes_pw`, `tk40_argon2d_chacha20_both` | `tom_kdbx` 2.4.2+tom.4 | KDBX 4.0, Argon2d (it writes no other) |
| `store010_document`, `store010_settings` | `tom_kdbx_store` 0.1.0 on `tom_kdbx` 2.4.2+tom.4 | a Webwork document (records by id, a history snapshot, a recycled record, a purged record, an asset entry, meta data) and a Webwork settings container (keys, tokens, locations, identity, a fragment group) |
| `keepass2_41_argon2id_chacha20_pw`, `keepass2_41_argon2d_aes_keyfile`, `keepass2_40_aeskdf_aes_both`, `keepass2_31_aeskdf_aes_pw`, `keepass2_31_aeskdf_aes_hexkey` | KeePass 2.62, the format's reference implementation | a KPScript C# script builds each database with KeePassLib on Windows. The 4.1 files are plain saves; the 4.0 and 3.1 files are saved with KeePass's version switch, the one its "KeePass KDBX (3.1)" export uses. KeePass 2.62 otherwise saves 4.0 at the least, and 4.1 once the meta holds custom data |
| `kxc_kp*` | KeePassXC 2.8.0 | each `kp*` file changed and saved by `keepassxc-cli`: an entry added with an attachment, an entry edited (history), a group made, an entry moved to the recycle bin. KeePassXC saves every file as KDBX 4.1, keeping its KDF and cipher |
| `kxc_created_both` | KeePassXC 2.8.0 | `keepassxc-cli db-create` (its defaults: KDBX 4.1, AES-KDF, AES), then entries, an attachment, an edit, a removal |

Every file written by `tom_kpasslib`, KeePass 2.x and `tom_kdbx` holds:
- plain and protected fields, including a custom protected field (`tom_kpasslib` and KeePass add unicode);
- a plain attachment (`tom_kpasslib` and KeePass also a protected one);
- two history versions;
- a custom icon and a subgroup;
- an entry in the recycle bin and a permanently deleted entry;
- meta custom data.

Beside each `<name>.kdbx`:

- `<name>.keepassxc.xml` — `keepassxc-cli export -f xml`: KeePassXC's reading of the file.
- `<name>.keepassxc.attachments.json` — the SHA-256 of every current entry's attachments, by entry path, as `keepassxc-cli attachment-export --stdout` gives them. The XML export names attachments but carries no contents.

`keys/` holds the key files: KeePass key file 2.0 (`corpus_v2.keyx`), 1.0
(`corpus_v1.key`) and 64 hex digits (`corpus_hex.key`). The password of every
file that has one is `corpus-demo`. These are demo keys; nothing they open is
real.

## How it is made

The generator imports `tom_kdbx` (GPL-3) and the old `tom_kdbx_store` 0.1.0, so
it lives outside this repository, in the Tom workspace's quest folder:
`_ai/quests/tom_core/ideas/tom_secrets_manager/kdbx_corpus/`. It needs
KeePassXC (`keepassxc-cli`). For the KeePass 2.x files it also needs SSH to a
Windows host with KeePass 2.x and KPScript (Chocolatey: `keepass`,
`keepass-plugin-kpscript`). That host is the fleet host legiondary01 by
default, or `KDBX_CORPUS_KEEPASS2_HOST`. Run it from that folder:

```sh
dart run bin/generate.dart <this package>/test/corpus
```

`--keepass2-only` writes only the KeePass 2.x files again and adds them to the
corpus there, leaving every other file as it is.

Beside it, `kdbx_migration_check/` reads every file with `tom_kdbx` and with
this package and compares them. It also has `tom_kdbx` read what this package
writes back.

## What it found

- **`tom_kpasslib` garbled a KDBX 3 file's protected values when the file has a protected binary.** The XML was built Root before Meta, so the stream took the binary's bytes out of document order. KeePassXC read garbage too. Fixed in 1.1.2+tom.3.
- **KeePassXC 2.8.0 saves KDBX 3.1 and 4.0 files as 4.1.**
- **`tom_kdbx` opens none of the Argon2id files, none of the KDBX 3.1 files `tom_kpasslib` wrote and none of those KeePass 2.62 wrote.** KeePassXC and this package open them all.
- **KeePass 2.62's files read the same in KeePassXC, `tom_kdbx` (where it opens them) and this package.** Written back by this package, they read the same in KeePassXC.
