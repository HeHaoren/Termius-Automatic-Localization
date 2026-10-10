# Termius 汉化自动更新脚本

自动检测 Termius 版本更新、下载对应汉化包并替换 `app.asar`，让 Termius 界面汉化可长期自动维护——Termius 每次自动更新后，脚本会在下次计划任务运行时自动重新汉化。

## 工作原理

```
检测版本 → 下载汉化包 → 关闭 asar 完整性校验 → 备份原版 → 替换 → 启动验证 → 崩溃则回滚
```

1. 读取本地 Termius 版本与汉化包最新版本
2. 版本变化时，从 ArcSurge/Termius-Pro-zh_CN 下载对应版本的汉化包
3. 关闭 Termius 的 `EnableEmbeddedAsarIntegrityValidation` 熔丝（**Termius v10+ 必需**，否则替换后的 asar 会被完整性校验拒绝、启动即退出）
4. 备份原版 `app.asar` 后替换为汉化包
5. 启动 Termius 验证，若崩溃则自动回滚到原版

## 前置要求

- Windows（PowerShell 5.1+）
- [Node.js](https://nodejs.org/)（供 `@electron/fuses` 使用）
- 网络可访问 GitHub

## 安装

```powershell
cd <本项目目录>
npm install @electron/fuses
```

## 使用

### 立即汉化一次

```powershell
powershell -ExecutionPolicy Bypass -File .\update-termius-localize.ps1 -Force
```

### 注册计划任务（登录时 + 每天自动检查）

```powershell
powershell -ExecutionPolicy Bypass -File .\register-task.ps1
```

计划任务每天运行一次、登录后延迟 3 分钟运行一次，每次都是轻量 no-op，仅在 Termius 版本变化或汉化包更新时才真正执行替换。

## 汉化包来源

汉化包由 ArcSurge/Termius-Pro-zh_CN 项目提供，脚本自动从其 Releases 下载 `app-windows-localize.asar`。感谢该项目的贡献。

> 替换 `app.asar` 后 Termius 无法启动（integrity check failed）的详细说明，见该项目的 [FAQ](https://github.com/ArcSurge/Termius-Pro-zh_CN#q3-%E6%9B%BF%E6%8D%A2-appasar-%E5%90%8E%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E5%90%AF%E5%8A%A8integrity-check-failed)。

## 安全机制

- **自动备份**：每次替换前备份原版 `app.asar` 到 `backup\` 目录（仅当当前文件仍为官方版时备份，避免用汉化版覆盖原始备份）
- **崩溃回滚**：替换后启动 Termius 验证，若进程未存活则自动回滚并恢复原版
- **版本校验**：下载失败退回本地缓存时校验缓存版本，版本不匹配拒绝使用，避免旧版汉化包套到新版 Termius 上

## 可选：阻止 Termius 自动更新

若不希望 Termius 自动更新（避免汉化反复失效），可删除安装目录下的更新配置：

```
%LOCALAPPDATA%\Programs\Termius\resources\app-update.yml
```

## 免责声明

本项目仅供学习交流使用。汉化涉及修改商业软件（Termius），请自行承担使用风险，并遵守相关软件的服务条款与当地法律法规。
