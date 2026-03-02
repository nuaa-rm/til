# Git SSH 443 端口配置

## 问题描述

在某些网络环境下，防火墙会阻断标准的 SSH 端口（22），导致无法使用 `git@github.com` 格式的 SSH 地址进行克隆、拉取或推送操作。

## 解决方案

将 Git SSH 连接切换到 443 端口（HTTPS 端口），该端口在大多数网络环境下都是开放的。

## 使用方法

```bash
cd /home/baiye/til/git疑难杂症/gitSSH端口配置
./setup-git-ssh-443.sh
```

## 脚本功能

1. **创建 SSH 配置文件** `~/.ssh/config`
   - 将 `github.com` 的连接重定向到 `ssh.github.com`
   - 指定使用 443 端口

2. **添加 GitHub 主机密钥** 到 `~/.ssh/known_hosts`

3. **测试连接** 验证配置是否成功

## 配置内容

执行后，`~/.ssh/config` 文件内容如下：

```
Host github.com
    Hostname ssh.github.com
    Port 443
    User git
```

## 前置条件

确保已生成 SSH 密钥并添加到 GitHub 账户：

```bash
# 生成密钥（如果没有）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 查看公钥
cat ~/.ssh/id_ed25519.pub

# 将公钥添加到 GitHub：Settings > SSH and GPG keys > New SSH key
```

## 验证配置

配置完成后，可以测试连接：

```bash
ssh -T git@github.com
```

成功会显示：`Hi username! You've successfully authenticated...`
