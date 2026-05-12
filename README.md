# ENA Metagenome Downloader

通过 ENA Portal API 下载 FASTQ 文件。**下载默认在 screen 后台运行**，退出终端也不会中断。

## 快速安装

```bash
git clone https://github.com/zhijianxiao/sra-download-skill.git
cd sra-download-skill
chmod +x download_sra.sh

# 基础依赖（必需）
sudo apt install curl wget screen

# 注释工具（可选，按需安装）
conda install -c bioconda fastqc seqkit kraken2
```

## 常用命令

| 场景 | 命令 |
|------|------|
| 下载单个 SRR | `bash download_sra.sh SRR11066123` |
| 下载整个项目 | `bash download_sra.sh PRJNA1074950` |
| 指定下载目录 | `bash download_sra.sh PRJNA1074950 /home/user/data` |
| 从 txt 列表批量下载 | `bash download_sra.sh --file my_list.txt /home/user/data` |
| 下载 + 生成报告 | `bash download_sra.sh PRJNA1074950 --report` |
| 下载 + 注释分析 | `bash download_sra.sh PRJNA1074950 --annotation` |
| 下载 + 报告 + 注释 | `bash download_sra.sh PRJNA1074950 --report --annotation` |
| 前台运行（不用 screen） | `bash download_sra.sh SRR11066123 --foreground` |

## 使用示例

### 1. 下载单个 Run

```bash
bash download_sra.sh SRR11066123
```

### 2. 下载整个 BioProject（PRJNA / PRJEB）

```bash
bash download_sra.sh PRJNA1074950 /home/user/downloads
```

自动解析项目下所有 SRR / ERR / DRR 并下载。

### 3. 从本地 txt 列表批量下载

创建 `my_list.txt`，每行一个 accession：

```
# 我的下载列表
SRR11066123
SRR11066124
ERR1234567
```

```bash
bash download_sra.sh --file my_list.txt /home/user/data
```

### 4. 下载并生成汇总报告

```bash
bash download_sra.sh PRJNA1074950 /home/user/downloads --report
```

下载完成后自动生成 `download_report.txt`，包含每个 Run 的状态、文件大小、总大小等。

### 5. 下载并进行注释分析

```bash
# 基础注释（fastqc + seqkit，需提前安装）
bash download_sra.sh PRJNA1074950 --annotation

# 含 Kraken2 分类（需提前下载数据库）
bash download_sra.sh PRJNA1074950 --annotation --annotation-db /path/to/kraken2_db
```

支持的注释工具（自动检测已安装的工具）：

| 工具 | 功能 | 安装 |
|------|------|------|
| FastQC | 测序质量报告 (.html) | `conda install fastqc` |
| seqkit | 序列统计 (stats.txt) | `conda install seqkit` |
| Kraken2 | 物种分类注释 | `conda install kraken2` |

### 6. 前台运行（调试用）

```bash
bash download_sra.sh SRR11066123 --foreground
```

## 查看下载进度 & 日志

| 操作 | 命令 |
|------|------|
| 查看所有 screen 会话 | `screen -list` |
| 进入会话看实时进度 | `screen -r PRJNA1074950` |
| 退出会话（不中断下载） | 按 `Ctrl+A` 再按 `D` |
| 实时查看日志 | `tail -f PRJNA1074950/download.log` |
| 停止下载 | `screen -S PRJNA1074950 -X quit` |

## 输出结构

```
/home/user/downloads/
└── PRJNA1074950/
    ├── SRR11066123_1.fastq.gz
    ├── SRR11066123_2.fastq.gz
    ├── SRR11066124.fastq.gz
    ├── ...
    ├── download.log
    ├── download_report.txt          # 使用 --report 时生成
    └── annotation/                  # 使用 --annotation 时生成
        ├── fastqc/                  #   FastQC HTML 报告
        ├── seqkit_stats.txt         #   seqkit 统计表
        └── kraken2/                 #   Kraken2 分类结果
```

## 参数说明

```
bash download_sra.sh <ACCESSION> [OUTPUT_DIR] [OPTIONS]
bash download_sra.sh --file <LIST.txt> [OUTPUT_DIR] [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `ACCESSION` | PRJNA / PRJEB / SRR / ERR / DRR ... |
| `OUTPUT_DIR` | 下载目录（可选，默认当前目录） |

| 选项 | 说明 |
|------|------|
| `--file FILE` | 从本地 txt 读取 accession 列表（每行一个，# 开头为注释） |
| `--report` | 下载完成后生成汇总报告 `download_report.txt` |
| `--annotation` | 下载完成后运行注释分析（fastqc, seqkit, kraken2） |
| `--annotation-db PATH` | Kraken2 数据库路径（自动启用 --annotation） |
| `--foreground` | 前台运行，不创建 screen 会话 |
| `--show-progress` | 强制显示进度条（终端下默认自动） |
| `-h, --help` | 显示帮助 |

默认行为：不加 `--report` / `--annotation` 则只下载数据。如果终端可用，启动时会询问是否需要报告和注释。

## 功能特点

- **默认后台运行** — 自动创建 screen 会话，断开 SSH 不中断
- **断点续传** — `wget -c` 支持中断恢复，已下载文件自动跳过
- **自动重试** — 下载失败自动重试 3 次
- **批量下载** — 支持 txt 列表一次性提交多个 accession
- **汇总报告** — `--report` 生成 `download_report.txt`，记录每个 Run 的状态、大小、耗时
- **注释分析** — `--annotation` 自动运行 FastQC / seqkit / Kraken2（仅检测已安装工具）
- **交互式提示** — 终端启动时询问是否需要报告和注释，回车跳过
- **日志完整** — 每个任务独立 `download.log`，记录耗时、大小、状态
- **无需 SRA Toolkit** — 直接下载 `.fastq.gz`
