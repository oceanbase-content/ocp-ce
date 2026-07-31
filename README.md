# OCP 文档源仓库

本仓库为 OCP 在线文档的 Markdown 源文件（`zh-CN/`、`en-US/`）。

## 上传文档包到 OSS

发版后，可将 yuque2book 等工具产出的文档 tar.gz 包直接上传到 OSS，供 OCP 前端拉取。

### 一次性配置

1. 复制环境变量模板：

```bash
cp .env
```

2. 在 `.env` 中复制 OSS 凭证（勿提交到 Git）。

### 上传文档包

```bash
# -v：OCP 版本号，决定 OSS 上的文件名（如 4.5.0.tar.gz）
# -f：本地文档包路径（可为绝对路径）
# -l：上传完成后列出 OSS 上所有版本
./script/docs-oss-manager.sh upload -v 4.5.0 -f "V4.5.0.tar.gz" -l
```

**版本号约定**：`-v` 须与 OCP 版本一致，格式为 `x.y.z` 或 `x.y.z-xxx`（如 `4.5.0`、`4.4.0-bp3`）。

### 其他命令

```bash
# 查看 OSS 上已有文档版本
./script/docs-oss-manager.sh list
```

### 上传后

上传完成后请通知相关同学，以便在流水线走构建流程验证文档
