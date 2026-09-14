# OCP 文档源仓库

本仓库为 OCP 在线文档的 Markdown 源文件（`zh-CN/`、`en-US/` ...）。

## 流水线构建并上传 OSS（推荐）

打包完成后会自动上传文档包到 OSS，供 OCP 前端拉取。

流水线构建使用快捷方式 **OSS**。使用时需要：

1. **修改分支名**：选择要构建的文档分支
2. **修改 `ACI_VAR_DOCS_VERSION` 变量**：文档版本号，决定 OSS 上的文件名（如 `4.5.0` → `4.5.0.tar.gz`）

**版本号约定**：须与 OCP 版本一致，格式为 `x.y.z` 或 `x.y.z-xxx`（如 `4.5.0`、`4.4.0-bp3`）。

上传完成后请通知相关同学，以便在前端流水线验证文档。

## 本地手动上传（本地测试）

### 一次性配置

1. 配置环境变量（勿提交到 Git，.gitignore 已忽略）：

```bash
# 在 .env 中填写 OSS 凭证（参考 .gitignore，勿提交）
```

2. 在 `.env` 中填写 OSS 相关变量（`ACI_VAR_OSS_PATH` / `ACI_VAR_OSS_AK` / `ACI_VAR_OSS_SK` / `ACI_VAR_OSS_ENDPOINT`）。

### 上传文档包

```bash
# -v：OCP 版本号，决定 OSS 上的文件名（如 4.5.0.tar.gz）
# -f：本地文档包路径（可为绝对路径）
# -l：上传完成后列出 OSS 上所有版本
./script/docs-oss-manager.sh upload -v 4.5.0 -f "docs.tar.gz" -l
```

### 其他命令

```bash
# 查看 OSS 上已有文档版本
./script/docs-oss-manager.sh list

# 下载指定版本（需先 mkdir -p public）
mkdir -p public
./script/docs-oss-manager.sh download -v 4.5.0
```
