# 备份自用的一些配置文件
## JetBrains激活（纯前端实现）
[JetBrains在线激活](https://0xwans.github.io/my-backup/JetBrains/JetBrains-Online.html)

[使用说明](https://0xwans.github.io/my-backup/JetBrains/)

## Clash覆写配置  
- [clash/config.yaml](clash/config.yaml)    


# MacBook 裸核教程
```bash
# 进入系统启动项管理
cd /Library/LaunchAgents
# 创建启动项
touch com.mihomo.plist
```

## 将文件内容写入`mihomo.plist`，需要自己修改路径

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>mihomo</string>
    <key>ProgramArguments</key>
    <array>
        <!-- 替换为你的 mihomo 可执行文件路径 -->
        <string>/path/mihomo</string>
        <!-- 可选：指定配置路径 -->
        <string>-d</string>
        <string>/path/mihomo/</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <!-- 日志存路径，自己设置 -->
    <string>/tmp/mihomo/clash-meta.log</string>
</dict>
</plist>
```
# 配置权限
```bash
# 更改为root用户
sudo chown root:wheel com.mihomo.plist
# 更改权限
sudo chmod 755 com.mihomo.plist
# 进入mihomo目录，将mihomo运行程序所属用户修改为root
sudo chown root:admin mihomo
# 设置 SUID 位，允许以 root 权限运行
sudo chmod u+s mihomo
```

## 启动
```bash
launchctl start mihomo

```
## 配置文件
（config.yaml）会在启动后自动生成
修改config.yaml，自己配置，或者用我的路径在clash/config.yaml
修改完之后执行`launchctl stop mihomo`会自动重启内核，重新加载配置文件