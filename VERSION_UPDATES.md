# LEMPer 软件依赖版本更新记录

更新基准日期：**2026-09-24**
更新原则：仅修改版本固定值及直接相关的下载 URL、注释说明；未重构任何脚本逻辑；未采用 RC / beta / alpha / nightly 版本；无法从官方来源核实的版本保持不变。

---

## 1. 已更新的版本（旧版 → 新版）

| 软件 | 旧版本 | 新版本（截至 2026-09-24 最新稳定） | 核实来源 | 修改文件 |
|---|---|---|---|---|
| Nginx（源码构建回退版） | 1.24.0 | 1.30.5（2026-09-02 发布） | github.com/nginx/nginx/releases | scripts/install_nginx.sh |
| OpenSSL / QuicTLS（Nginx 自定义 SSL） | openssl-3.1.5-quic1 | openssl-3.5.8（LTS，2026-08-25） | github.com/openssl/openssl/releases | .env.dist、scripts/nginx/nginx_ssl_builders.sh、lemper.sh |
| PCRE → PCRE2 | 8.45（PCRE1） | 10.48（2026 年发布） | github.com/PCRE2Project/pcre2/releases（下载 URL 已验证 200） | .env.dist、scripts/nginx/nginx_ssl_builders.sh、lemper.sh |
| Go（BoringSSL 构建用） | 1.17.8 | 1.27.1 | go.dev/dl/?mode=json（下载 URL 已验证 200） | scripts/nginx/nginx_ssl_builders.sh |
| LuaJIT（OpenResty 分支） | v2.1-20240626 | v2.1-20260914 | github.com/openresty/luajit2/tags | .env.dist、scripts/nginx/nginx_extra_modules.sh |
| lua-resty-core | v0.1.28 | v0.1.32 | github.com/openresty/lua-resty-core/tags（排除 rc） | .env.dist、scripts/nginx/nginx_extra_modules.sh |
| lua-resty-lrucache | v0.13 | v0.15 | github.com/openresty/lua-resty-lrucache/tags（排除 rc） | .env.dist、scripts/nginx/nginx_extra_modules.sh |
| lua-nginx-module | v0.10.26 | v0.10.31 | github.com/openresty/lua-nginx-module/tags（v0.10.32 仍为 rc，不用） | .env.dist、scripts/nginx/nginx_extra_modules.sh |
| PHP（可用版本 / 默认版本） | 8.1 8.2 8.3 / 默认 8.2 | 8.3 8.4 8.5 / 默认 8.5（8.5.11 为 2026-09-22 发布最新补丁） | php.net 官方发布公告（8.6.0 仅 RC1，不用） | .env.dist、scripts/install_php.sh、lib/lemper-create.sh、README.md |
| Phalcon（cphalcon） | 4.1.2（默认）、v5.0.0-alpha.2（5.x 选项） | 5.20.3（2026-08-26） | github.com/phalcon/cphalcon（tarball URL 已验证 200） | .env.dist、scripts/install_phalcon.sh |
| Zephir | 0.12.19 | 1.5.0（2026-09-18） | github.com/phalcon/zephir/releases（git ls-remote 匹配模式同步改为 `1.*`） | .env.dist、scripts/install_phalcon.sh |
| ImageMagick | 7.1.0-21 | 7.1.2-31（2026-09-03） | github.com/ImageMagick/ImageMagick（下载 URL 已验证 200） | .env.dist、scripts/install_imagemagick.sh |
| MariaDB | 11.1 | 13.0（13.0.2，2026-09-17 宣布 stable） | mariadb.org 官方公告 | .env.dist、scripts/install_mariadb.sh |
| PostgreSQL | 17 | 18（PG19 仍为 beta） | apt.postgresql.org PGDG 仓库（18/noble 路径已验证 200） | .env.dist、scripts/install_postgres.sh、scripts/remove_postgres.sh |
| MongoDB | 6.0（默认）/ 7.0（bookworm） | 8.0 | repo.mongodb.org 官方 apt 仓库（trixie、noble 的 8.0 路径已验证 200） | .env.dist、scripts/install_mongodb.sh |
| Fail2ban | 1.1.0 | 1.1.1（2026-08-15） | github.com/fail2ban/fail2ban/releases（tarball URL 已验证 200） | .env.dist、scripts/install_fail2ban.sh |
| Python（源码/PPA 安装用） | 3.13.0 / 3.13 | 3.14.4 / 3.14 | python.org FTP（3.14.4 已验证 200；3.15.0 不存在） | .env.dist、scripts/install_dependencies.sh |
| GitHub Actions checkout | v2 | v7 | github.com/actions/checkout/releases | .github/workflows/main.yml |

### 备注

- Nginx 配置 `NGINX_VERSION="stable"` / Redis `"stable"` / Memcached `"latest"` / FTP `"latest"` 保持动态解析不变，截至 2026-09-24 它们分别对应：Nginx 1.30.5、Redis 8.10.1、Memcached 1.6.45、Pure-FTPd/Vsftpd 各自最新（注释中的示例版本号已同步更新）。
- PHP 交互式安装菜单新增 8.5 选项（编号顺延），8.1 标注改为 EOL（其安全支持已于 2025-12-31 结束），8.5 标注为 Latest Stable。
- Phalcon 交互菜单中 5.x 选项由 `v5.0.0-alpha.2` 改为 `5.20.3`，状态标注由 `[Alpha]` 改为 `[Latest stable]`；4.x 标注由 `[Latest]` 改为 `[EOL]`。

---

## 2. 未修改项（保持不变）

| 软件 | 当前值 | 原因 |
|---|---|---|
| AdminerEvo | 4.8.4 | 已核实仍为官方最新 release（截至 2026-09-24 无更新版本） |
| TinyFileManager | lemperfm_1.3.0（项目自定义分支） | 为 LEMPer 自有分支，无上游官方版本可对标 |
| Node.js | 无安装实现 | install_nodejs.sh 仅为占位注释，无版本 pin 可更新 |
| Composer | 动态安装（无固定版本） | 无版本固定值，未改动 |
| ionCube Loader | 动态下载（无固定版本） | 无版本固定值，未改动 |
| MariaDB jessie 回退版 10.5 | 10.5 | 针对已 EOL 的 Debian Jessie 的旧版回退逻辑，保持原样 |
| MariaDB bionic 回退版 11.1 | 11.1 | 针对已 EOL 的 Ubuntu Bionic 的旧版回退逻辑，保持原样 |
| Phalcon 4.x 分支 pin 4.1.2 | 4.1.2 | 4.x 分支的最新/最终版本仍为 4.1.2，保持原样 |
| lua-nginx-stream-module | master | 无稳定 tag，原配置即为 master，保持原样 |

---

## 3. 无法从官方来源核实、保持不变的项

无。本次所有修改的版本号均已通过官方来源（GitHub releases/tags、官方发布公告、官方仓库 HTTP 200 验证）核实。

---

## 4. 已知问题与注意事项（需人工复核）

1. **PCRE1 → PCRE2 迁移**：`build_pcre()` 的下载 URL 已从 SourceForge PCRE1 切换为 PCRE2Project GitHub release，解压目录由 `pcre-` 改为 `pcre2-`。Nginx `--with-pcre` 指向 PCRE2 源码目录在 Nginx ≥ 1.21.5 受支持（本项目目标为 1.30.x），但实际构建兼容性建议在目标系统上验证一次。
2. **QuicTLS 已停止开发**（2025-04 起）：`NGINX_CUSTOMSSL_VERSION` 默认值由 `openssl-3.1.5-quic1` 改为官方 `openssl-3.5.8`；OpenSSL 3.5 LTS（至 2030-04）已内置 QUIC 支持，仍可构建 `--with-http_v3_module`。
3. **ImageMagick 下载源变更**：`download.imagemagick.org/.../releases/` 目录已不再托管 7.1.2-31（返回 404，旧版本会被移走），已改为官方 GitHub tag 归档 URL（`github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.2-31.tar.gz`，已验证 200）。归档格式由 `.tar.xz` 变为 `.tar.gz`，脚本使用 `tar -xf` 自动识别，解压目录名仍匹配 `ImageMagick-*/`。
4. **Phalcon 版本门控逻辑**：`install_phalcon.sh` 中按版本号分支选择安装包的逻辑（`version_older_than` 判断）未改动；5.x 走 `repo` 安装器时仍沿用旧的分支映射，建议后续按需重构该逻辑。
5. **MariaDB 13.0 非 LTS**：13.0 为 rolling stable 系列（13.0.2），若生产环境要求 LTS，可手动改用 12.3 LTS。
6. **MongoDB 8.0**：采用官方标准支持版本 8.0（非 rapid 版 8.2/8.3），已验证 trixie/noble 官方仓库路径可用。
7. **deadsnakes PPA Python 3.14**：Ubuntu focal/jammy/noble 改用 `python3.14`，依赖 deadsnakes PPA 已提供对应构建；若某旧发行版缺失该包，脚本会报错（原行为同样依赖 PPA）。
8. **GitHub Actions checkout v2 → v7**：v7 要求 Node 24 运行环境，对应 CI 运行器若过旧可能需要同步升级 runner。

---

## 5. 验证结果

- 所有 14 个修改过的 `.sh` 文件已执行 `bash -n`，全部通过：
  lemper.sh、lib/lemper-create.sh、scripts/install_dependencies.sh、scripts/install_fail2ban.sh、scripts/install_imagemagick.sh、scripts/install_mariadb.sh、scripts/install_mongodb.sh、scripts/install_nginx.sh、scripts/install_phalcon.sh、scripts/install_php.sh、scripts/install_postgres.sh、scripts/nginx/nginx_extra_modules.sh、scripts/nginx/nginx_ssl_builders.sh、scripts/remove_postgres.sh
- 关键下载 URL 均已通过 HTTP HEAD 验证返回 200（详见上表）。
- 未创建任何 Git commit，变更保留在工作区（`git status` 显示 17 个文件已修改）。
