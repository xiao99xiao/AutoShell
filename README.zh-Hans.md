# AutoShell

[English](README.md) · 简体中文

<img src="logos/export/logo-192.png" width="96" height="96" alt="AutoShell logo">

一个原生 SwiftUI macOS 菜单栏工具，用于管理本地常驻 Shell 任务。

## 语言

英文是默认和回退语言，目前提供英文与简体中文。App 跟随 macOS 的语言偏好，也支持系统为单个 App 指定语言；重新打开 App 后生效。

界面、菜单、无障碍标签、校验错误和 AutoShell 生成的日志提示统一使用 `AutoShell/Localizable.xcstrings`。任务名称、命令和命令输出保持原样。新增语言时在 Xcode 的 String Catalog 添加翻译即可，不需要修改业务代码。

## 使用

1. 在 Xcode 中选择 AutoShell scheme，运行 App。首次启动会打开管理窗口。
2. 点击「添加任务」，填写名称、Shell 命令和工作目录。
3. 勾选「随 AutoShell 启动」，保存后点击「启动任务」做首次验证。保存本身不会执行命令。
4. 将稳定位置的 AutoShell.app 添加到「系统设置 → 通用 → 登录项与扩展 → 登录时打开」。管理窗口左下角可打开该设置。不要将临时构建目录中的 App 用作长期登录项。
5. 从菜单栏查看各任务状态，启动、停止、重启，或打开管理窗口查看日志。

### GitHub Actions Runner 示例

先按 GitHub 的说明完成 runner 下载和 `config.sh` 配置，然后添加：

- 名称：`GitHub Runner`
- 工作目录：你实际的 `actions-runner` 文件夹
- 命令：`./run.sh`
- 随 AutoShell 启动：开启
- 失败后自动重启：默认关闭，按需开启

任务应保持前台运行。不要使用 `&`、`nohup`、`disown` 或 daemon 模式，也不要同时用另一套服务管理工具启动同一个 runner。

## 行为

- 关闭管理窗口，任务继续运行；退出 AutoShell，先发送 SIGTERM 到任务进程组，5 秒后强制结束尚未退出的进程。
- 重新启动会等待旧任务退出，重复点击启动不会产生重复进程。
- 默认失败后停留在失败状态，显示退出码。可选自动恢复只在非零退出时触发，等待从 5 秒递增到最多 60 秒。手动停止会取消等待；稳定运行超过 60 秒后重置退避。
- 使用指定 Shell 的 `-l -c` 模式（默认 `/bin/zsh`）：读取登录配置，但不自动读取 `.zshrc`。如命令依赖 nvm、conda、别名等交互配置，请在命令中显式初始化，或使用可执行文件绝对路径。常用 Homebrew 路径会加入初始 PATH，但登录配置仍可覆盖它。
- 自定义环境变量每行 `KEY=value`，值按原样传入，不需要 Shell 引号或变量展开。配置是本地明文文件，仅当前用户可读写。
- 命令没有交互输入，stdin 来自 `/dev/null`。sudo 密码提示、交互式 TUI、需要真正终端的命令请在 Terminal 中运行。工具本身可能缓存输出，可使用其无缓冲参数（如 Python 的 `-u`）。

## 定时重启

选择任务，在「定时重启」旁点击「设置…」，开启「按间隔重复重启」，输入秒、分钟、小时或天数（至少 1 秒）。运行中也可以修改或关闭，设置会按任务保存。

保存设置或启动任务时开始计时。到期后先结束当前进程组，等待退出，再启动新进程并重新计时。详情页显示完整的开始日期、下次重启日期、已运行时长和实时倒计时；时长支持天、小时、分钟、秒。日志会记录每次定时重启。

关闭窗口不会中断计时。手动停止任务或退出 AutoShell 会取消当前倒计时；下次启动任务时，按已保存的间隔恢复。意外退出仍遵循「失败后自动重启」设置，默认由你手动处理。AutoShell 需要保持运行，不会唤醒电脑；睡眠期间到期的重启会在唤醒后执行一次，再重新计时。

## 日志

标准输出和标准错误合并记录。App 显示最近 128 KB，支持搜索、暂停显示、跟随和复制。每个任务保留当前日志及一个归档，各最多 5 MB。

「在 Terminal 查看」打开 `tail -F` 跟踪当前日志，支持日志轮转。它是只读日志窗口，不是附着到正在运行的进程；按 Control-C 只会结束查看，不会停止任务。

数据位置：

```text
~/Library/Application Support/AutoShell/
  tasks.json
  Logs/<task-id>.log
  Logs/<task-id>.log.1
  Terminal/<task-id>.command
```

删除任务只删除配置，保留已有日志。配置损坏时会提示错误并阻止覆盖原文件。

## 边界

这是由 App 管理的前台命令工具，不是 launchd 服务管理器。正常退出会清理任务进程组；强制退出、App 崩溃或任务自行脱离进程组时不保证清理，重新启动前应确认旧进程是否仍在运行。电脑睡眠时不能保证命令继续执行。

为了访问本地工作目录及运行工具，App Sandbox 已关闭，保留 Hardened Runtime。项目保持 Xcode 模板的 macOS 26.5 部署版本。

## 开发与验证

```sh
xcodebuild -scheme AutoShell -configuration Debug \
  -derivedDataPath /tmp/AutoShell-build build CODE_SIGNING_ALLOWED=NO

./Tests/run.sh
./Tests/test-localizations.sh
```

集成测试在独立临时目录中运行真实子进程，覆盖配置持久化、自动启动、stdout/stderr、工作目录与环境变量、退出码、重复启动、进程组终止、强制停止、重启顺序、取消自动恢复、日志轮转、退出清理及损坏配置保护。需要 macOS 和 Xcode Command Line Tools，不依赖外部包。
