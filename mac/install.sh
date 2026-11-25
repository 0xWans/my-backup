#!/bin/bash
set -e

# 设置代理
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890

# 安装 Homebrew
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# 安装 Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    # 语法高亮插件
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
    # 自动补全插件
    git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions
    # 自动目录插件
    brew install autojump
fi

# 安装 pyenv, goenv 和 jenv
for tool in pyenv goenv jenv; do
    if ! command -v $tool &> /dev/null; then
        brew install $tool
    fi
done
SHELL_CONFIG="$HOME/.zshrc"  # 或者 "$HOME/.zshrc" 根据你的 shell 类型选择
sed -i '' 's/ZSH_THEME="robbyrussell"/ZSH_THEME="avit"/' "$SHELL_CONFIG"
sed -i '' 's/plugins=()/plugins=(\n    git\n    zsh-autosuggestions\n    zsh-syntax-highlighting\n    autojump\n)/' "$SHELL_CONFIG"
sed -i '' 's/# DISABLE_MAGIC_FUNCTIONS="true"/DISABLE_MAGIC_FUNCTIONS="true"/' "$SHELL_CONFIG"
#!/bin/bash

add_config() {
    local marker="$1"
    shift
    local config="$@"

    if ! grep -q "$marker" "$SHELL_CONFIG"; then
        {
            echo "$marker"
            echo "$config"
        } >> "$SHELL_CONFIG"
    fi
}

# 添加终端代理配置
add_config '# 终端代理' '
port=7890
bport=8080
hostip=127.0.0.1
set_proxy() {
    local proxy_port=$1
    export https_proxy="http://${hostip}:${proxy_port}"
    export http_proxy="http://${hostip}:${proxy_port}"
    export all_proxy="socks5://${hostip}:${proxy_port}"
    export ALL_PROXY="socks5://${hostip}:${proxy_port}"
    echo "set proxy:"
    env | grep -i proxy
}
clear_proxy() {
    unset https_proxy
    unset http_proxy
    unset all_proxy
    unset ALL_PROXY
    echo "clear proxy:"
    env | grep -i proxy
}
alias y="set_proxy ${port}"
alias yb="set_proxy ${bport}"
alias n="clear_proxy"
'

# 添加 pyenv 配置
add_config '# pyenv' '
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/shims:$PATH"
export PATH="$PYENV_ROOT/bin:$PATH"
pyenv() {
    eval "$(command pyenv init -)"
    pyenv "$@"
}
'

# 添加 goenv 配置
add_config '# goenv' '
export GOENV_ROOT="$HOME/.goenv"
export PATH="$GOENV_ROOT/shims:$PATH"
export PATH="$GOENV_ROOT/bin:$PATH"
goenv() {
    eval "$(command goenv init -)"
    goenv "$@"
}
'

# 添加 nvm 配置
add_config '# nvm' '
export NVM_DIR="$HOME/.nvm"
export PATH="$NVM_DIR/versions/node/v20.14.0/bin:$PATH"
nvm() {
    . "$NVM_DIR/nvm.sh" ; nvm "$@"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
'

# 添加 jenv 配置
add_config '# jenv' '
export JENV_ROOT="$HOME/.jenv"
export PATH="$JENV_ROOT/shims:$PATH"
export PATH="$JENV_ROOT/bin:$PATH"
eval "$(command jenv init -)"
'

# 添加 Maven 配置
add_config '# maven' '
export MAVEN_HOME=/Volumes/Data/Program/maven/apache-maven-3.9.7
export PATH="${MAVEN_HOME}/bin:${PATH}"
export PATH="$PATH:/Applications/010 Editor.app/Contents/CmdLine" #ADDED BY 010 EDITOR
'

add_config '# JetBrains VMOptions' '
___MY_VMOPTIONS_SHELL_FILE="${HOME}/.jetbrains.vmoptions.sh"; if [ -f "${___MY_VMOPTIONS_SHELL_FILE}" ]; then . "${___MY_VMOPTIONS_SHELL_FILE}"; fi
'

# 配置java环境至jenv
# 遍历 /Volumes/Data/Program/Java/ 目录下的所有 JDK 版本
for jdk_path in /Volumes/Data/Program/Java/jdk-*.jdk; do
    # 提取 JDK 版本号
    jdk=$(basename "$jdk_path" | awk -F 'jdk-|\\.jdk' '{print $2}')

    # 检查 jenv 中是否已经存在该 JDK 版本
    if jenv versions | grep -q "$jdk"; then
        echo "JDK $jdk 已经存在于 jenv 中，跳过添加。"
        continue
    fi

    # 检查 JDK 的安装目录是否存在
    if [ ! -d "$jdk_path/Contents/Home/" ]; then
        echo "JDK $jdk 不存在，跳过添加。"
        continue
    fi

    # 添加 JDK 到 jenv
    jenv add "$jdk_path/Contents/Home/"
    echo "JDK $jdk 已成功添加到 jenv。"
done

# 检查 Java 是否已安装
if /usr/libexec/java_home &> /dev/null; then
    echo "Java 已安装。"
    # 提示用户选择操作
    echo "请选择操作："
    echo "1) 解决默认使用JRE的问题（冰蝎）"
    echo "2) 利用jenv实现双击jar版本切换"
    read -p "请输入选项 (1 或 2)默认为 3: " option
    option=${option:-3}
    case $option in
        1)
            # 解决默认使用 JRE 的问题
            echo "正在修改 Java 控制面板中的环境变量..."
            sudo rm -f /Library/Internet\ Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/bin/java
            sudo ln -s /Library/Java/JavaVirtualMachines/jdk-1.8.jdk/Contents/Home/bin/java /Library/Internet\ Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/bin/java
            echo "已成功创建软连接。"
            ;;
        2)
            # 利用 jenv 实现双击版本切换
            echo "正在创建 jenv 的软连接..."
            sudo ln -s /Users/mac/.jenv/shims/java /Library/Internet\ Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/bin/java
            echo "jenv 软连接已创建。"
            ;;
        *)
            echo "无效的选项，请输入 1 或 2。"
            ;;
    esac
else
    echo "未安装 JDK，正在安装..."
    # 将磁盘自带的 Java 环境添加到系统中
    sudo cp -R /Volumes/Data/Program/Java/jdk-1.8.jdk /Library/Java/JavaVirtualMachines/
    echo "JDK 已安装。"
fi

# 配置python环境
if ! command -v pyenv &> /dev/null; then
    pyenv install 2.7.18
    pyenv install 3.11.11
    pyenv global 3.11.11
    # 配置pip代理
    pip config set global.proxy http://127.0.0.1:7890
fi

# 配置golang语言环境
if ! command -v goenv &> /dev/null; then
    goenv install 1.22.10
    goenv global 1.22.10
    brew install goreleaser/tap/goreleaser
    # 配置golang代理
    go env -w GOPROXY=https://goproxy.io,http://127.0.0.1:7890
fi

# nvm
if ! command -v nvm &> /dev/null; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/refs/heads/master/install.sh | bash
    # 重新加载 nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    nvm install --lts
    npm config set proxy http://127.0.0.1:7890
    npm config set https-proxy http://127.0.0.1:7890
fi


# 配置 Git 代理和用户信息
git config --global http.proxy 'http://127.0.0.1:7890'
git config --global https.proxy 'http://127.0.0.1:7890'
git config --global user.name "0xWans"
git config --global user.email **@qq.com"

# upx
if [ ! -f /usr/local/bin/upx ]; then
    ln -s /Volumes/Data/Program/upx-4.2.4/opt/local/bin/upx /usr/local/bin/upx
fi
echo "Setup completed successfully!"
