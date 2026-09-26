# DSH Desktop 专业部署包

> DSH Desktop 企业级一键部署解决方案
> 版本 1.0.0 · 构建 2026-01-15

## 简介

DSH Desktop（DeepSeek Harness 桌面版）是一个跨平台桌面客户端，用于连接 DeepSeek Harness AI 编码代理。

本部署包提供**工程化的部署工具、配套文档与技术支持**，面向个人用户和企业 IT 管理员。

## 快速开始

### 个人用户

`
1. 解压本压缩包
2. 双击 1-一键安装.bat
3. 按提示完成安装
`

### 企业批量部署

`powershell
# 静默安装（推荐）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-DSH.ps1 -Silent -Force -NoLaunch -NoPause

# 离线安装（内网环境）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-DSH.ps1 -Silent -Force -NoLaunch -NoPause -Offline
`

详见 docs/03-部署手册.md 和 docs/07-企业批量部署.md。

## 目录结构

`
DSH-Desktop-专业部署包-v1.0.0/
├── 1-一键安装.bat          # 主安装入口
├── 2-环境检测.bat          # 环境预检与诊断
├── 3-卸载程序.bat          # 卸载工具
├── VERSION.txt             # 版本信息
├── 使用前必读.txt          # 快速上手入口
├── scripts/
│   ├── Common.ps1          # 公共库（界面/日志/下载/编码）
│   ├── Install-DSH.ps1     # 安装引擎
│   ├── Test-DSHEnvironment.ps1 # 环境诊断引擎
│   └── Uninstall-DSH.ps1   # 卸载引擎
├── docs/                   # 完整文档（10 份）
│   ├── 01-产品介绍.md
│   ├── 02-快速入门.md
│   ├── 03-部署手册.md
│   ├── 04-使用手册.md
│   ├── 05-常见问题.md
│   ├── 06-故障排查.md
│   ├── 07-企业批量部署.md
│   ├── 08-售后服务.md
│   └── 09-许可协议与免责声明.md
└── logs/                   # 运行时日志
    └── 说明.txt
`

## 特性

- **六步标准化安装**：检测 → 检查 → 获取 → 安装 → 验证 → 清理
- **双下载源自动切换**：官方源 + GitHub 备用，单源 3 次重试
- **实时下载进度条**：进度百分比、文件大小、下载速度
- **安装包完整性校验**：PE 文件头验证 + 体积合理性检查
- **数字签名识别**：自动检测 Authenticode 签名状态
- **20+ 项环境预检**：系统、架构、磁盘、内存、权限、网络、干扰项
- **一键导出诊断报告**：用于技术支持快速定位问题
- **中文双宽字符对齐渲染**：横幅、表格、进度条均不错位
- **完整日志留痕**：便于售后问题排查
- **安装记录写入**：时间、版本、路径、校验值、机器、用户
- **企业静默部署支持**：约定退出码，适配 SCCM/Intune
- **离线部署支持**：内置安装包，无需外网
- **数据安全优先**：静默模式默认不强制关闭用户程序
- **卸载数据可选保留**：个人数据保留/清除二选一

## 系统要求

- 操作系统：Windows 10 / 11（64 位）
- PowerShell：≥ 5.1
- 系统盘可用空间：≥ 3 GB
- 网络连接：首次安装需要（离线部署除外）

## 退出码约定

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 通用失败 |
| 2 | 不满足系统要求 |
| 3 | 下载失败 |
| 4 | 安装失败 |
| 5 | 验证失败 |
| 6 | 用户取消 |

## 关于目标应用

DSH Desktop 是采用 [MIT 许可证](https://opensource.org/licenses/MIT) 发布的免费开源软件，
由 DataElement 开发。本部署包**不销售目标应用本身**，而是提供部署工具、文档与技术支持服务。

更多信息请查看 docs/09-许可协议与免责声明.md。

## 技术支持

详见 docs/08-售后服务.md。

---

*本文档为 DSH Desktop 专业部署包的一部分。*
