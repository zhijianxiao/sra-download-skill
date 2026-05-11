# ENA Metagenome Downloader

通过 ENA Portal API 批量下载指定项目（PRJNA / PRJEB）或单个 Run（SRR / ERR / DRR）的 FASTQ 文件。

## 快速开始

```bash
git clone https://github.com/zhijianxiao/sra-download-skill.git
cd sra-download-skill
chmod +x download_sra.sh

# 下载整个项目
bash download_sra.sh PRJNA1074950 --output-dir /mnt/hdd2/cxj-download/metagenome

# 下载单个 SRR
bash download_sra.sh SRR11066123 --output-dir ./data

# 后台运行（screen）
bash download_sra.sh PRJNA1074950 --output-dir /mnt/hdd2/cxj-download/metagenome --background
screen -r PRJNA1074950  # 查看进度
```

---

## download_sra.sh（推荐）

统一的下载脚本，支持项目级和单 Run 级下载。

### 用法

```bash
bash download_sra.sh <ACCESSION> [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `ACCESSION` | PRJNA / PRJEB（项目）或 SRR / ERR / DRR（单个 Run） |

| 选项 | 说明 |
|------|------|
| `--output-dir DIR` | 下载目录（默认 `./output`） |
| `--show-progress` | 强制显示 wget 进度条（终端下默认自动开启） |
| `--background` | 在 screen 会话中后台运行，session 名 = ACCESSION |
| `-h, --help` | 显示帮助 |

### 功能特点

- **项目 + 单 Run** — 自动识别输入类型，PRJNA 解析全部 SRR / ERR
- **ENA 直链下载** — 无需 SRA Toolkit，直接下载 `.fastq.gz`
- **断点续传** — `wget -c` 支持中断恢复，已存在文件自动跳过
- **自动重试** — 下载失败自动重试 3 次，间隔 5 秒
- **实时进度** — 终端显示 wget 进度条（文件名、大小、速度、ETA）
- **日志记录** — 每个项目目录下生成 `download.log`，记录开始/结束时间、每个 SRR 状态、文件大小、错误信息
- **Screen 后台运行** — `--background` 一键启动后台下载，断连不中断
- **自动创建目录** — `mkdir -p` 自动创建输出目录和项目子目录

### 输出结构

```
<output-dir>/
└── PRJNA1074950/
    ├── SRR11066123_1.fastq.gz
    ├── SRR11066123_2.fastq.gz
    ├── SRR11066124.fastq.gz
    └── download.log
```

- 文件直接存放在项目目录下，无嵌套子目录
- 仅保留 `.fastq.gz` 文件和 `download.log`，不保留中间文件

### 日志格式

```log
============================================================
Download Started:  2026-05-11 14:30:00
Accession:         PRJNA1074950
Accession Type:    project
Output Directory:  /mnt/hdd2/cxj-download/metagenome/PRJNA1074950
============================================================

[1/2] SRR11066123 (PAIRED) — START
  [OK] SRR11066123_1.fastq.gz — 2.3GB (00:05:21)
  [OK] SRR11066123_2.fastq.gz — 2.1GB (00:04:58)
[1/2] SRR11066123 — DONE (00:10:19)

============================================================
Download Finished: 2026-05-11 14:40:19
Elapsed:           00:10:19
Success:           2/2
============================================================
```

### 环境要求

| 依赖 | 说明 |
|------|------|
| `curl` | 查询 ENA API |
| `wget` | 下载 FASTQ 文件（支持断点续传和进度条） |
| `screen` | 后台运行（仅 `--background` 时需要） |
| Bash 4.0+ | Linux / WSL |

```bash
# Ubuntu / Debian
sudo apt install curl wget screen
```

---

## download_ena.sh（旧版，保留兼容）

仅支持项目级下载，输出目录硬编码为 `/mnt/hdd2/cxj-download/metagenome`。

```bash
bash download_ena.sh <PROJECT_ID>
```

## run_in_screen.sh（旧版，保留兼容）

```bash
bash run_in_screen.sh <ACCESSION>
```

常用 screen 命令：

```bash
screen -r PRJNA210709         # 恢复会话，查看实时进度
screen -list                  # 列出所有会话
screen -S PRJNA210709 -X quit # 手动终止
```
