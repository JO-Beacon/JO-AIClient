# Pinned Android sandbox runtime

`proot-5.1.107.95.tar.xz` 里是给 ARMv7、ARM64、x86_64 三个架构用的 12 个运行时
库，取自以下 Termux 包：

- PRoot 5.1.107.95
- libtalloc 2.4.3
- libandroid-shmem 0.7

放进仓库是因为 Termux 的包池是滚动更新的，旧版本会被删掉，届时构建会直接失败。
Android 构建用 `tool/fetch_proot.sh` 从这份归档还原；脚本会先用
`tool/proot_checksums.txt` 逐个文件校验，全部通过后才替换任何一份本地运行时。

归档内是普通文件，路径形如 `<abi>/<库名>.so`。

来源与许可证说明见
[`android/app/src/main/jniLibs/NOTICE`](../../android/app/src/main/jniLibs/NOTICE)。

升级运行时的方法：取出三个架构的新上游包、替换这份归档，并把校验单与 NOTICE
一起改掉。
