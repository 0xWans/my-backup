# Windows 工具箱

交互式 PowerShell 脚本:迁移用户文件夹到其他盘、修改临时文件目录、清理临时文件、查看激活状态。

## 使用

```powershell
irm https://cdn.jsdelivr.net/gh/0xWans/my-backup@main/Windows/Windows-Toolbox.ps1 | iex
```

需要管理员权限的功能(系统级 TEMP、清理 `C:\Windows\Temp`),请先以管理员身份打开 PowerShell。

## 功能

```
[1] 用户文件夹
      迁移用户文件夹(可选择目标盘) / 查看当前路径 / 恢复默认路径
[2] 软件与存储位置
      创建软件安装目录 / 打开新内容保存位置设置 / 修改临时文件目录
[3] 清理与系统
      清理临时文件 / 查看 Windows 激活状态
```

## 注意

- 迁移是移动:先复制并校验,通过后才删除 C 盘原文件,完成后需注销或重启。
- 恢复默认路径只改指向,不会把文件搬回 C 盘。
