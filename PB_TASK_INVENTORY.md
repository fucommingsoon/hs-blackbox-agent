# PB Task Inventory

Canonical local ProgramBench task inventory for DTC fusion. This file is generated from local task metadata, not from the older AFL prediction notes.

## Source

- Metadata root: `/Users/kangxin/.cache/uv/archive-v0/sTrhsMs9voIeKDQ8/programbench/data/tasks`
- Per task files: `task.yaml` and `tests.json`
- Count basis: one directory under the metadata root equals one PB task

## Counts

| bucket | tasks |
|---|---:|
| hard | 18 |
| medium | 120 |
| easy | 28 |
| unknown | 35 |
| total | 201 |

Notes:

- `unknown` means the current `task.yaml` has no `difficulty` field. Do not drop these tasks; classify them before PB-wide planning.
- Older notes such as `../haskell_test_pb/pb_full_afl_prediction.md` cover 163 tasks and are historical AFL ROI estimates, not the full inventory.
- `test_count` is the sum of listed pytest node ids across all branches in `tests.json`; it is a scale signal, not a DTC coverage score.

## Hard Tasks (18)

| task | lang | repo | commit | branches | ignored branches | test_count |
|---|---|---|---|---:|---:|---:|
| `ariga__atlas.6d81150` | go | `ariga/atlas` | `6d81150` | 16 | 0 | 1732 |
| `canop__broot.d6c798e` | rs | `Canop/broot` | `d6c798e` | 9 | 0 | 850 |
| `dandavison__delta.acd758f` | rs | `dandavison/delta` | `acd758f` | 11 | 0 | 1188 |
| `doxygen__doxygen.966d98e` | c | `doxygen/doxygen` | `966d98e` | 9 | 0 | 252 |
| `ffmpeg__ffmpeg.360a402` | c | `FFmpeg/FFmpeg` | `360a402` | 12 | 0 | 4165 |
| `hairyhenderson__gomplate.05eb3aa` | go | `hairyhenderson/gomplate` | `05eb3aa` | 12 | 0 | 3538 |
| `jesseduffield__lazygit.1d0db51` | go | `jesseduffield/lazygit` | `1d0db51` | 12 | 0 | 1167 |
| `johnkerl__miller.8d85b46` | go | `johnkerl/miller` | `8d85b46` | 13 | 0 | 16070 |
| `paradigmxyz__solar.5190d0e` | rs | `paradigmxyz/solar` | `5190d0e` | 10 | 0 | 2528 |
| `parcel-bundler__lightningcss.aa2ed1e` | rs | `parcel-bundler/lightningcss` | `aa2ed1e` | 8 | 0 | 3155 |
| `php__php-src.c891263` | c | `php/php-src` | `c891263` | 10 | 0 | 20530 |
| `quinn-rs__quinn.bb359cc` | rs | `quinn-rs/quinn` | `bb359cc` | 8 | 0 | 620 |
| `rvben__rumdl.2d75c4d` | rs | `rvben/rumdl` | `2d75c4d` | 12 | 0 | 4781 |
| `skeema__skeema.6a76243` | go | `skeema/skeema` | `6a76243` | 12 | 0 | 3807 |
| `stacked-git__stgit.430027d` | rs | `stacked-git/stgit` | `430027d` | 12 | 0 | 2340 |
| `stranger6667__jsonschema.d52e881` | rs | `Stranger6667/jsonschema` | `d52e881` | 9 | 0 | 3006 |
| `typst__typst.88356d0` | rs | `typst/typst` | `88356d0` | 10 | 0 | 1789 |
| `unhappychoice__gittype.34b72d0` | rs | `unhappychoice/gittype` | `34b72d0` | 9 | 0 | 932 |

## Medium Tasks (120)

| task | lang | repo | commit | branches | ignored branches | test_count |
|---|---|---|---|---:|---:|---:|
| `agourlay__zip-password-finder.704700d` | rs | `agourlay/zip-password-finder` | `704700d` | 16 | 0 | 792 |
| `alexpovel__srgn.89f943b` | rs | `alexpovel/srgn` | `89f943b` | 17 | 0 | 2080 |
| `altdesktop__i3-style.f93821b` | rs | `altdesktop/i3-style` | `f93821b` | 17 | 0 | 750 |
| `ammarabouzor__tui-journal.2b4540d` | rs | `AmmarAbouZor/tui-journal` | `2b4540d` | 22 | 0 | 1839 |
| `antonmedv__fx.86d0d34` | go | `antonmedv/fx` | `86d0d34` | 16 | 0 | 3157 |
| `antonmedv__walk.bf802ef` | go | `antonmedv/walk` | `bf802ef` | 16 | 0 | 786 |
| `astro__deadnix.d590041` | rs | `astro/deadnix` | `d590041` | 14 | 0 | 709 |
| `axodotdev__oranda.27d60c7` | rs | `axodotdev/oranda` | `27d60c7` | 15 | 0 | 978 |
| `bensadeh__tailspin.6278437` | rs | `bensadeh/tailspin` | `6278437` | 13 | 0 | 785 |
| `blacknon__hwatch.edfcb62` | rs | `blacknon/hwatch` | `edfcb62` | 14 | 0 | 1321 |
| `bootandy__dust.62bf1e1` | rs | `bootandy/dust` | `62bf1e1` | 13 | 0 | 965 |
| `brocode__fblog.3b54330` | rs | `brocode/fblog` | `3b54330` | 13 | 0 | 1127 |
| `burntsushi__ripgrep.3b7fd44` | rs | `BurntSushi/ripgrep` | `3b7fd44` | 13 | 0 | 2538 |
| `burntsushi__xsv.f430466` | rs | `BurntSushi/xsv` | `f430466` | 12 | 0 | 1323 |
| `byron__dua-cli.8570c15` | rs | `Byron/dua-cli` | `8570c15` | 13 | 0 | 1003 |
| `canop__rhit.ae90bcb` | rs | `Canop/rhit` | `ae90bcb` | 14 | 0 | 1088 |
| `chmln__handlr.90e78ba` | rs | `chmln/handlr` | `90e78ba` | 12 | 0 | 908 |
| `chmln__sd.87d1ba5` | rs | `chmln/sd` | `87d1ba5` | 13 | 0 | 869 |
| `codesnap-rs__codesnap.f81e4f3` | rs | `codesnap-rs/codesnap` | `f81e4f3` | 14 | 0 | 871 |
| `cordx56__rustowl.655bc5c` | rs | `cordx56/rustowl` | `655bc5c` | 9 | 0 | 763 |
| `crowdagger__crowbook.ea214d7` | rs | `crowdagger/crowbook` | `ea214d7` | 10 | 0 | 887 |
| `cweill__gotests.2a672c5` | go | `cweill/gotests` | `2a672c5` | 10 | 0 | 752 |
| `dalance__amber.69a0f52` | rs | `dalance/amber` | `69a0f52` | 12 | 0 | 785 |
| `danmar__cppcheck.0a5b103` | cpp | `danmar/cppcheck` | `0a5b103` | 11 | 0 | 2550 |
| `direnv__direnv.02040c7` | go | `direnv/direnv` | `02040c7` | 11 | 0 | 986 |
| `ducaale__xh.4a6e44f` | rs | `ducaale/xh` | `4a6e44f` | 9 | 0 | 1266 |
| `dundee__gdu.ede21d2` | go | `dundee/gdu` | `ede21d2` | 12 | 0 | 1553 |
| `ecumene__rust-sloth.051c559` | rs | `ecumene/rust-sloth` | `051c559` | 11 | 0 | 455 |
| `ekzhang__bore.8e059cd` | rs | `ekzhang/bore` | `8e059cd` | 9 | 0 | 452 |
| `elkowar__pipr.fae0b17` | rs | `elkowar/pipr` | `fae0b17` | 11 | 0 | 835 |
| `epistates__treemd.825c6dd` | rs | `Epistates/treemd` | `825c6dd` | 13 | 0 | 1961 |
| `esubaalew__run.0fb9dec` | rs | `Esubaalew/run` | `0fb9dec` | 10 | 0 | 1507 |
| `eudoxia0__hashcards.48aa136` | rs | `eudoxia0/hashcards` | `48aa136` | 11 | 0 | 1293 |
| `facebook__zstd.1168da0` | c | `facebook/zstd` | `1168da0` | 14 | 0 | 2372 |
| `foriequal0__git-trim.07c2f50` | rs | `foriequal0/git-trim` | `07c2f50` | 12 | 0 | 726 |
| `gabotechs__dep-tree.60a95a2` | go | `gabotechs/dep-tree` | `60a95a2` | 12 | 0 | 1428 |
| `ggreer__the_silver_searcher.a61f178` | c | `ggreer/the_silver_searcher` | `a61f178` | 12 | 0 | 1192 |
| `git-bahn__git-graph.87b4473` | rs | `git-bahn/git-graph` | `87b4473` | 10 | 0 | 733 |
| `go-critic__go-critic.9aea378` | go | `go-critic/go-critic` | `9aea378` | 10 | 0 | 925 |
| `guumaster__hostctl.d6d9699` | go | `guumaster/hostctl` | `d6d9699` | 12 | 0 | 1385 |
| `halitechallenge__halite.822cfb6` | cpp | `HaliteChallenge/Halite` | `822cfb6` | 12 | 0 | 391 |
| `hatoo__oha.8dc6349` | rs | `hatoo/oha` | `8dc6349` | 12 | 0 | 1095 |
| `hooklift__gowsdl.2a06cec` | go | `hooklift/gowsdl` | `2a06cec` | 10 | 0 | 419 |
| `hpjansson__chafa.dd4d4c1` | c | `hpjansson/chafa` | `dd4d4c1` | 11 | 0 | 2775 |
| `htop-dev__htop.523600b` | c | `htop-dev/htop` | `523600b` | 2 | 0 | 1200 |
| `hush-shell__hush.560c33a` | rs | `hush-shell/hush` | `560c33a` | 10 | 0 | 1298 |
| `incu6us__goimports-reviser.81bd549` | go | `incu6us/goimports-reviser` | `81bd549` | 11 | 0 | 597 |
| `ismaelgv__rnr.fc0733b` | rs | `ismaelgv/rnr` | `fc0733b` | 11 | 0 | 742 |
| `isona__dirble.e2dea9f` | rs | `Isona/dirble` | `e2dea9f` | 13 | 0 | 1108 |
| `jarun__nnn.cb2c535` | c | `jarun/nnn` | `cb2c535` | 11 | 0 | 1796 |
| `johanneskaufmann__html-to-markdown.3006818` | go | `JohannesKaufmann/html-to-markdown` | `3006818` | 12 | 0 | 974 |
| `jonas__tig.8334123` | c | `jonas/tig` | `8334123` | 12 | 0 | 2239 |
| `jqlang__jq.b33a763` | c | `jqlang/jq` | `b33a763` | 12 | 0 | 6796 |
| `jrnxf__thokr.09375ef` | rs | `jrnxf/thokr` | `09375ef` | 9 | 0 | 507 |
| `junegunn__fzf.b56d614` | go | `junegunn/fzf` | `b56d614` | 11 | 0 | 2164 |
| `kaushiksrini__parqeye.8072121` | rs | `kaushiksrini/parqeye` | `8072121` | 12 | 0 | 564 |
| `konradsz__igrep.aa75630` | rs | `konradsz/igrep` | `aa75630` | 13 | 0 | 728 |
| `ksxgithub__parallel-disk-usage.96978ed` | rs | `KSXGitHub/parallel-disk-usage` | `96978ed` | 10 | 0 | 630 |
| `kyoh86__richgo.313114f` | go | `kyoh86/richgo` | `313114f` | 12 | 0 | 787 |
| `kyoheiu__felix.95df390` | rs | `kyoheiu/felix` | `95df390` | 10 | 0 | 979 |
| `lfos__calcurse.49180d5` | c | `lfos/calcurse` | `49180d5` | 12 | 0 | 1994 |
| `lua__lua.c6b4848` | c | `lua/lua` | `c6b4848` | 11 | 0 | 1387 |
| `luajit__luajit.a553b3d` | c | `LuaJIT/LuaJIT` | `a553b3d` | 8 | 0 | 3183 |
| `lymphatus__caesium-clt.a529b2e` | rs | `Lymphatus/caesium-clt` | `a529b2e` | 9 | 0 | 616 |
| `lz4__lz4.1519f46` | c | `lz4/lz4` | `1519f46` | 12 | 0 | 1829 |
| `madler__pigz.fe4894f` | c | `madler/pigz` | `fe4894f` | 10 | 0 | 938 |
| `mfridman__tparse.2416b4b` | go | `mfridman/tparse` | `2416b4b` | 10 | 0 | 556 |
| `mgechev__revive.201451e` | go | `mgechev/revive` | `201451e` | 8 | 0 | 886 |
| `mkj__dropbear.75f699b` | c | `mkj/dropbear` | `75f699b` | 10 | 0 | 1075 |
| `mookid__diffr.2152742` | rs | `mookid/diffr` | `2152742` | 11 | 0 | 782 |
| `naggie__dstask.ff57396` | go | `naggie/dstask` | `ff57396` | 12 | 0 | 1589 |
| `nikoladucak__caps-log.2cf2d1e` | cpp | `NikolaDucak/caps-log` | `2cf2d1e` | 12 | 0 | 1232 |
| `nikolassv__bartib.6b9b5ce` | rs | `nikolassv/bartib` | `6b9b5ce` | 13 | 0 | 929 |
| `ninja-build__ninja.cc60300` | cpp | `ninja-build/ninja` | `cc60300` | 13 | 0 | 1905 |
| `noborus__ov.b96c2ba` | go | `noborus/ov` | `b96c2ba` | 13 | 0 | 2447 |
| `noborus__trdsql.d8c5ff6` | go | `noborus/trdsql` | `d8c5ff6` | 11 | 0 | 1403 |
| `nuta__nsh.bdd0702` | rs | `nuta/nsh` | `bdd0702` | 14 | 0 | 2289 |
| `o2sh__onefetch.e5958ce` | rs | `o2sh/onefetch` | `e5958ce` | 9 | 0 | 1214 |
| `ogham__dog.721440b` | rs | `ogham/dog` | `721440b` | 10 | 0 | 1722 |
| `oppiliappan__eva.41ae245` | rs | `oppiliappan/eva` | `41ae245` | 9 | 0 | 963 |
| `oppiliappan__statix.e9df54c` | rs | `oppiliappan/statix` | `e9df54c` | 12 | 0 | 983 |
| `orf__gping.26eb5b9` | rs | `orf/gping` | `26eb5b9` | 8 | 0 | 655 |
| `peco__peco.4e58dad` | go | `peco/peco` | `4e58dad` | 11 | 0 | 1715 |
| `pemistahl__grex.fa3e8ed` | rs | `pemistahl/grex` | `fa3e8ed` | 9 | 0 | 1518 |
| `pier-cli__pier.5e1bde9` | rs | `pier-cli/pier` | `5e1bde9` | 8 | 0 | 779 |
| `pls-rs__pls.4e1ae50` | rs | `pls-rs/pls` | `4e1ae50` | 1 | 0 | 354 |
| `raviqqe__muffet.a882908` | go | `raviqqe/muffet` | `a882908` | 7 | 0 | 432 |
| `rhysd__kiro-editor.4157485` | rs | `rhysd/kiro-editor` | `4157485` | 8 | 0 | 770 |
| `riquito__tuc.16fb471` | rs | `riquito/tuc` | `16fb471` | 9 | 0 | 1249 |
| `robertdavidgraham__masscan.b99d433` | c | `robertdavidgraham/masscan` | `b99d433` | 7 | 0 | 3357 |
| `rochacbruno__marmite.7d4bc2d` | rs | `rochacbruno/marmite` | `7d4bc2d` | 9 | 0 | 853 |
| `rust-embedded__svd2rust.1760b5e` | rs | `rust-embedded/svd2rust` | `1760b5e` | 10 | 0 | 985 |
| `rust-ethereum__ethabi.b1710ad` | rs | `rust-ethereum/ethabi` | `b1710ad` | 10 | 0 | 1053 |
| `rust-lang__mdbook.37273ba` | rs | `rust-lang/mdBook` | `37273ba` | 12 | 0 | 1326 |
| `sayanarijit__xplr.1751065` | rs | `sayanarijit/xplr` | `1751065` | 8 | 0 | 939 |
| `segmentio__chamber.5f93f5f` | go | `segmentio/chamber` | `5f93f5f` | 11 | 0 | 3104 |
| `sharkdp__fd.40d8eb3` | rs | `sharkdp/fd` | `40d8eb3` | 10 | 0 | 1405 |
| `sharkdp__hexyl.2e26437` | rs | `sharkdp/hexyl` | `2e26437` | 11 | 0 | 974 |
| `sharkdp__pastel.b60e899` | rs | `sharkdp/pastel` | `b60e899` | 11 | 0 | 1256 |
| `shashwatah__jot.a92aad8` | rs | `shashwatah/jot` | `a92aad8` | 10 | 0 | 846 |
| `sibprogrammer__xq.b89f681` | go | `sibprogrammer/xq` | `b89f681` | 11 | 0 | 879 |
| `simeg__eureka.df3796c` | rs | `simeg/eureka` | `df3796c` | 12 | 0 | 400 |
| `sitkevij__hex.61ae69b` | rs | `sitkevij/hex` | `61ae69b` | 10 | 0 | 877 |
| `sstadick__hck.b66c751` | rs | `sstadick/hck` | `b66c751` | 9 | 0 | 884 |
| `svenstaro__miniserve.8449e8b` | rs | `svenstaro/miniserve` | `8449e8b` | 9 | 0 | 440 |
| `tarka__xcp.5e5b448` | rs | `tarka/xcp` | `5e5b448` | 8 | 0 | 1236 |
| `thezoraiz__ascii-image-converter.d05a757` | go | `TheZoraiz/ascii-image-converter` | `d05a757` | 9 | 0 | 488 |
| `tomarrell__wrapcheck.c058da1` | go | `tomarrell/wrapcheck` | `c058da1` | 10 | 0 | 669 |
| `trasta298__keifu.3331426` | rs | `trasta298/keifu` | `3331426` | 10 | 0 | 413 |
| `tree-sitter__tree-sitter.5e23cca` | rs | `tree-sitter/tree-sitter` | `5e23cca` | 11 | 0 | 1888 |
| `tukaani-project__xz.1007bf0` | c | `tukaani-project/xz` | `1007bf0` | 9 | 0 | 2036 |
| `wgunderwood__tex-fmt.3f1aef6` | rs | `WGUNDERWOOD/tex-fmt` | `3f1aef6` | 8 | 0 | 495 |
| `xampprocky__tokei.505d648` | rs | `XAMPPRocky/tokei` | `505d648` | 8 | 0 | 760 |
| `y2z__monolith.8702e66` | rs | `Y2Z/monolith` | `8702e66` | 9 | 0 | 777 |
| `yaa110__nomino.f892499` | rs | `yaa110/nomino` | `f892499` | 7 | 0 | 338 |
| `yassinebridi__serpl.c48a9d7` | rs | `yassinebridi/serpl` | `c48a9d7` | 8 | 0 | 536 |
| `yoav-lavi__melody.f4af9b4` | rs | `yoav-lavi/melody` | `f4af9b4` | 9 | 0 | 1438 |
| `ys-l__flamelens.0b4dc33` | rs | `YS-L/flamelens` | `0b4dc33` | 8 | 0 | 311 |
| `zevv__duc.a58fa4e` | c | `zevv/duc` | `a58fa4e` | 8 | 0 | 1246 |
| `zk-org__zk.10d93d5` | go | `zk-org/zk` | `10d93d5` | 10 | 0 | 1473 |

## Easy Tasks (28)

| task | lang | repo | commit | branches | ignored branches | test_count |
|---|---|---|---|---:|---:|---:|
| `abishekvashok__cmatrix.5c082c6` | c | `abishekvashok/cmatrix` | `5c082c6` | 14 | 0 | 769 |
| `anordal__shellharden.6a6ffd4` | rs | `anordal/shellharden` | `6a6ffd4` | 15 | 0 | 1292 |
| `arthursonzogni__json-tui.17a22b6` | cpp | `ArthurSonzogni/json-tui` | `17a22b6` | 15 | 0 | 894 |
| `astaxie__bat.17d1080` | go | `astaxie/bat` | `17d1080` | 15 | 0 | 1462 |
| `clog-tool__clog-cli.7066cba` | rs | `clog-tool/clog-cli` | `7066cba` | 10 | 0 | 778 |
| `cmatsuoka__figlet.202a0a8` | c | `cmatsuoka/figlet` | `202a0a8` | 12 | 0 | 1044 |
| `cslarsen__jp2a.61d205f` | c | `cslarsen/jp2a` | `61d205f` | 11 | 0 | 714 |
| `drew-alleman__datasurgeon.d257cee` | rs | `Drew-Alleman/DataSurgeon` | `d257cee` | 8 | 0 | 564 |
| `eliukblau__pixterm.1a93fd5` | go | `eliukblau/pixterm` | `1a93fd5` | 6 | 0 | 458 |
| `eradman__entr.8e2e8b4` | c | `eradman/entr` | `8e2e8b4` | 11 | 0 | 685 |
| `kisielk__errcheck.dacab89` | go | `kisielk/errcheck` | `dacab89` | 10 | 0 | 532 |
| `mgdm__htmlq.6e31bc8` | rs | `mgdm/htmlq` | `6e31bc8` | 10 | 0 | 2058 |
| `mibk__dupl.1bf052b` | go | `mibk/dupl` | `1bf052b` | 10 | 0 | 450 |
| `miserlou__loop.209927c` | rs | `Miserlou/Loop` | `209927c` | 11 | 0 | 778 |
| `multiprocessio__dsq.c3ae0ba` | go | `multiprocessio/dsq` | `c3ae0ba` | 10 | 0 | 766 |
| `nachoparker__dutree.44e877d` | rs | `nachoparker/dutree` | `44e877d` | 11 | 0 | 957 |
| `psampaz__go-mod-outdated.bb79367` | go | `psampaz/go-mod-outdated` | `bb79367` | 9 | 0 | 342 |
| `rbakbashev__elfcat.52f8cc7` | rs | `rbakbashev/elfcat` | `52f8cc7` | 13 | 0 | 646 |
| `rs__curlie.5dfcbb1` | go | `rs/curlie` | `5dfcbb1` | 10 | 0 | 741 |
| `rs__jplot.2a54bcc` | go | `rs/jplot` | `2a54bcc` | 8 | 0 | 722 |
| `sclevine__yj.8016400` | go | `sclevine/yj` | `8016400` | 9 | 0 | 825 |
| `sheepla__pingu.926d475` | go | `sheepla/pingu` | `926d475` | 8 | 0 | 419 |
| `sirwart__ripsecrets.34c9e03` | rs | `sirwart/ripsecrets` | `34c9e03` | 10 | 0 | 937 |
| `testorg__calculator.abc1234` | bash | `testorg/calculator` | `abc1234` | 1 | 0 | 3 |
| `wfxr__code-minimap.0ddeea5` | rs | `wfxr/code-minimap` | `0ddeea5` | 8 | 0 | 370 |
| `wfxr__csview.8ac4de0` | rs | `wfxr/csview` | `8ac4de0` | 7 | 0 | 348 |
| `wintermute-cell__ngrrram.8ea13c3` | rs | `wintermute-cell/ngrrram` | `8ea13c3` | 6 | 0 | 332 |
| `xorg62__tty-clock.f2f847c` | c | `xorg62/tty-clock` | `f2f847c` | 6 | 0 | 319 |

## Unknown Tasks (35)

| task | lang | repo | commit | branches | ignored branches | test_count |
|---|---|---|---|---:|---:|---:|
| `ajeetdsouza__zoxide.67ca1bc` | rs | `ajeetdsouza/zoxide` | `67ca1bc` | 2 | 0 | 577 |
| `alecthomas__chroma.8d04def` | go | `alecthomas/chroma` | `8d04def` | 1 | 0 | 531 |
| `arq5x__bedtools2.dd57059` | c | `arq5x/bedtools2` | `dd57059` | 1 | 0 | 1093 |
| `ast-grep__ast-grep.dde0fe0` | rs | `ast-grep/ast-grep` | `dde0fe0` | 1 | 0 | 895 |
| `bellard__quickjs.d7ae12a` | c | `bellard/quickjs` | `d7ae12a` | 1 | 0 | 3044 |
| `blake3-team__blake3.15e83a5` | rs | `BLAKE3-team/BLAKE3` | `15e83a5` | 1 | 0 | 687 |
| `boyter__scc.515f91c` | go | `boyter/scc` | `515f91c` | 1 | 0 | 476 |
| `cheat__cheat.b8098dc` | go | `cheat/cheat` | `b8098dc` | 1 | 0 | 307 |
| `chirlu__sox.42b3557` | c | `chirlu/sox` | `42b3557` | 2 | 0 | 1260 |
| `duckdb__duckdb.bdb65ec` | cpp | `duckdb/duckdb` | `bdb65ec` | 3 | 0 | 8958 |
| `facebookresearch__fasttext.1142dc4` | cpp | `facebookresearch/fastText` | `1142dc4` | 2 | 0 | 352 |
| `filosottile__age.706dfc1` | go | `FiloSottile/age` | `706dfc1` | 2 | 0 | 839 |
| `google__brotli.b3dc9cc` | c | `google/brotli` | `b3dc9cc` | 2 | 0 | 606 |
| `gromacs__gromacs.665ea4c` | cpp | `gromacs/gromacs` | `665ea4c` | 1 | 0 | 1382 |
| `ip7z__7zip.839151e` | cpp | `ip7z/7zip` | `839151e` | 2 | 0 | 1085 |
| `ivanceras__svgbob.6d00ad9` | rs | `ivanceras/svgbob` | `6d00ad9` | 2 | 0 | 474 |
| `jgm__pandoc.5caad90` | hs | `jgm/pandoc` | `5caad90` | 2 | 0 | 5467 |
| `jhspetersson__fselect.c3559ca` | rs | `jhspetersson/fselect` | `c3559ca` | 2 | 0 | 3435 |
| `lh3__seqtk.94e7070` | c | `lh3/seqtk` | `94e7070` | 2 | 0 | 440 |
| `mikefarah__yq.602586d` | go | `mikefarah/yq` | `602586d` | 2 | 0 | 2046 |
| `nukesor__pueue.8b9d6fe` | rs | `Nukesor/pueue` | `8b9d6fe` | 2 | 0 | 1223 |
| `osgeo__gdal.0847f12` | cpp | `OSGeo/gdal` | `0847f12` | 2 | 0 | 1319 |
| `osgeo__proj.75d455c` | cpp | `OSGeo/PROJ` | `75d455c` | 2 | 0 | 7160 |
| `rcoh__angle-grinder.9c2fc88` | rs | `rcoh/angle-grinder` | `9c2fc88` | 2 | 0 | 1143 |
| `samtools__samtools.aa823b5` | c | `samtools/samtools` | `aa823b5` | 2 | 0 | 1819 |
| `sharkdp__bat.f822bd0` | rs | `sharkdp/bat` | `f822bd0` | 2 | 0 | 986 |
| `sharkdp__hyperfine.327d5f4` | rs | `sharkdp/hyperfine` | `327d5f4` | 1 | 0 | 298 |
| `sigoden__argc.04a08f1` | rs | `sigoden/argc` | `04a08f1` | 2 | 0 | 1410 |
| `sqlite__sqlite.839433d` | c | `sqlite/sqlite` | `839433d` | 2 | 0 | 16801 |
| `stathissideris__ditaa.f2286c4` | java | `stathissideris/ditaa` | `f2286c4` | 2 | 0 | 681 |
| `svenstaro__genact.16f96e3` | rs | `svenstaro/genact` | `16f96e3` | 1 | 0 | 237 |
| `tinycc__tinycc.9b8765d` | c | `tinycc/tinycc` | `9b8765d` | 2 | 0 | 2062 |
| `tomnomnom__gron.88a6234` | go | `tomnomnom/gron` | `88a6234` | 1 | 0 | 233 |
| `tstack__lnav.ee34494` | cpp | `tstack/lnav` | `ee34494` | 1 | 0 | 1172 |
| `universal-ctags__ctags.243595e` | c | `universal-ctags/ctags` | `243595e` | 2 | 0 | 2579 |
