#!/bin/bash
# Feishu Card Bot 启动脚本
# 支持本地开发和内网穿透两种模式

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 打印带颜色的消息
print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 信号处理 - 清理后台进程
cleanup() {
    print_msg "\n🛑 正在清理进程..." $YELLOW
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        kill "$FLASK_PID"
        print_msg "✅ Flask进程已终止" $GREEN
    fi
    if [[ -n "$TUNNEL_PID" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
        kill "$TUNNEL_PID"
        print_msg "✅ 隧道进程已终止" $GREEN
    fi
    print_msg "👋 再见!" $CYAN
    exit 0
}

trap cleanup SIGINT SIGTERM

# 检查系统依赖
check_system_dependencies() {
    print_header "检查系统依赖"
    
    local missing_deps=()
    
    # 检查基础工具
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    # 检查编译工具 (对于Pillow编译)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - 检查是否有Xcode Command Line Tools
        if ! xcode-select -p &>/dev/null; then
            print_msg "⚠️ Xcode Command Line Tools未安装，Pillow可能编译失败" $YELLOW
            print_msg "安装方法: xcode-select --install" $CYAN
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - 检查编译依赖
        local linux_deps=("gcc" "python3-dev")
        for dep in "${linux_deps[@]}"; do
            if ! command -v "$dep" &> /dev/null && ! dpkg -l | grep -q "$dep" 2>/dev/null; then
                missing_deps+=("$dep")
            fi
        done
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_msg "⚠️ 缺少系统依赖: ${missing_deps[*]}" $YELLOW
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            print_msg "安装方法: sudo apt-get install ${missing_deps[*]}" $CYAN
        fi
    else
        print_msg "✅ 系统依赖检查通过" $GREEN
    fi
}

# 检查Python环境
check_python() {
    if ! command -v python3 &> /dev/null; then
        print_msg "❌ Python3 未安装，请先安装Python3" $RED
        exit 1
    fi
    
    local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    local major_version=$(echo "$python_version" | cut -d'.' -f1)
    local minor_version=$(echo "$python_version" | cut -d'.' -f2)
    
    # 检查Python版本是否在支持范围内 (3.9-3.13)
    if [[ $major_version -ne 3 ]] || [[ $minor_version -lt 9 ]] || [[ $minor_version -gt 13 ]]; then
        print_msg "❌ Python版本不受支持: $python_version" $RED
        print_msg "支持的版本范围: Python 3.9 - 3.13" $YELLOW
        exit 1
    fi
    
    print_msg "✅ Python版本: $python_version (支持)" $GREEN
    
    # 特别提示Python 3.13的新特性
    if [[ $minor_version -eq 13 ]]; then
        print_msg "💡 检测到Python 3.13，使用最新依赖版本以获得最佳兼容性" $CYAN
    fi
}

# 设置虚拟环境
setup_venv() {
    print_header "设置Python虚拟环境"
    
    if [ ! -d ".venv" ]; then
        print_msg "📦 创建虚拟环境..." $BLUE
        if ! python3 -m venv .venv; then
            print_msg "❌ 虚拟环境创建失败" $RED
            print_msg "可能原因: 缺少python3-venv包或权限问题" $YELLOW
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                print_msg "尝试安装: sudo apt-get install python3-venv" $CYAN
            fi
            exit 1
        fi
        print_msg "✅ 虚拟环境创建完成" $GREEN
    else
        print_msg "✅ 虚拟环境已存在" $GREEN
    fi

    # 检查虚拟环境是否可用
    if [ ! -f ".venv/bin/python" ]; then
        print_msg "❌ 虚拟环境损坏，重新创建中..." $YELLOW
        rm -rf .venv
        python3 -m venv .venv
    fi

    # 检查依赖是否需要更新
    print_msg "📋 检查依赖..." $BLUE
    if ! .venv/bin/pip install --upgrade pip -q; then
        print_msg "⚠️ pip升级失败，继续使用当前版本" $YELLOW
    fi
    
    # 增强的依赖安装逻辑
    local need_install=false
    local install_failed=false
    
    # 检查requirements.txt中的包是否已安装且版本匹配
    while IFS= read -r package; do
        if [[ -n "$package" && ! "$package" =~ ^# ]]; then
            package_name=$(echo "$package" | cut -d'=' -f1)
            if ! .venv/bin/pip show "$package_name" &>/dev/null; then
                need_install=true
                break
            fi
        fi
    done < requirements.txt
    
    if $need_install; then
        print_msg "📦 安装项目依赖..." $BLUE
        
        # 尝试安装依赖，如果失败提供诊断信息
        if ! .venv/bin/pip install -r requirements.txt -q; then
            print_msg "❌ 依赖安装失败，尝试详细安装以获取错误信息..." $RED
            install_failed=true
            
            # 逐个安装以定位问题
            while IFS= read -r package; do
                if [[ -n "$package" && ! "$package" =~ ^# ]]; then
                    print_msg "📦 安装 $package ..." $BLUE
                    if ! .venv/bin/pip install "$package"; then
                        print_msg "❌ $package 安装失败" $RED
                        
                        # 针对Pillow提供特殊诊断
                        if [[ "$package" =~ ^Pillow ]]; then
                            print_msg "💡 Pillow安装失败常见解决方案:" $CYAN
                            if [[ "$OSTYPE" == "darwin"* ]]; then
                                echo "  - 安装Xcode Command Line Tools: xcode-select --install"
                                echo "  - 或安装完整Xcode开发工具"
                            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                                echo "  - 安装编译依赖: sudo apt-get install python3-dev libjpeg-dev zlib1g-dev"
                                echo "  - 或使用预编译wheel: pip install --only-binary=pillow Pillow"
                            fi
                        fi
                    else
                        print_msg "✅ $package 安装成功" $GREEN
                    fi
                fi
            done < requirements.txt
        fi
    fi
    
    # python-dotenv现在已包含在requirements.txt中，不需要单独检查
    
    if $install_failed; then
        print_msg "⚠️ 部分依赖安装可能有问题，但将继续尝试启动" $YELLOW
    else
        print_msg "✅ 依赖检查完成" $GREEN
    fi
}

# 配置环境文件
setup_env() {
    print_header "配置环境文件"
    
    if [ ! -f ".env" ]; then
        print_msg "📝 创建.env配置文件..." $BLUE
        cp .env.example .env
        print_msg "⚠️ 请编辑.env文件，填入你的飞书应用ID和密钥" $YELLOW
        print_msg "配置文件位置: $(pwd)/.env" $CYAN
    else
        print_msg "✅ .env文件已存在" $GREEN
    fi
}

# 清理冲突进程
cleanup_conflicting_processes() {
    print_header "清理冲突进程"
    
    # 检查是否有占用3000端口的进程
    local conflicting_pids=$(lsof -ti :3000 2>/dev/null || true)
    
    if [[ -n "$conflicting_pids" ]]; then
        print_msg "🔍 发现占用3000端口的进程: $conflicting_pids" $YELLOW
        print_msg "🧹 正在清理冲突进程..." $BLUE
        
        # 优雅地终止进程
        for pid in $conflicting_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                print_msg "  终止进程: $pid" $CYAN
                kill "$pid" 2>/dev/null || true
                sleep 1
                
                # 如果进程仍然存在，强制终止
                if kill -0 "$pid" 2>/dev/null; then
                    print_msg "  强制终止进程: $pid" $YELLOW
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        done
        
        # 等待端口释放
        sleep 2
        
        # 再次检查
        local remaining_pids=$(lsof -ti :3000 2>/dev/null || true)
        if [[ -n "$remaining_pids" ]]; then
            print_msg "⚠️ 仍有进程占用3000端口: $remaining_pids" $YELLOW
            print_msg "请手动终止这些进程或使用其他端口" $RED
            return 1
        else
            print_msg "✅ 端口3000已清理完毕" $GREEN
        fi
    else
        print_msg "✅ 端口3000无冲突进程" $GREEN
    fi
    
    # 清理可能的Flask僵尸进程
    local flask_pids=$(pgrep -f "python.*app.py" 2>/dev/null || true)
    if [[ -n "$flask_pids" ]]; then
        print_msg "🔍 发现Flask相关进程: $flask_pids" $YELLOW
        print_msg "🧹 正在清理Flask进程..." $BLUE
        
        for pid in $flask_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                print_msg "  终止Flask进程: $pid" $CYAN
                kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
            fi
        done
        
        sleep 1
        print_msg "✅ Flask进程清理完毕" $GREEN
    fi
    
    return 0
}

# 检查服务状态
check_service() {
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:3000/healthz &>/dev/null; then
            print_msg "✅ 服务启动成功 (尝试 $attempt/$max_attempts)" $GREEN
            return 0
        fi
        
        print_msg "⏳ 等待服务启动... ($attempt/$max_attempts)" $YELLOW
        sleep 1
        attempt=$((attempt + 1))
    done
    
    print_msg "❌ 服务启动失败或超时" $RED
    return 1
}

# 显示测试选项
show_test_options() {
    print_msg "\n🧪 可用的测试工具:" $PURPLE
    echo "  - 运行 './local_test.py' 进行完整功能测试"
    echo "  - 运行 './batch_test.sh' 进行批量测试" 
    echo "  - 打开 'test_page.html' 进行可视化测试"
    echo "  - 访问 'http://localhost:3000/healthz' 检查服务状态"
    print_msg "\n💡 推荐先运行本地测试验证功能正常！" $CYAN
}

# 本地运行模式
run_local() {
    print_header "本地开发模式"
    
    # 清理可能的进程冲突
    cleanup_conflicting_processes || {
        print_msg "❌ 进程清理失败，无法启动服务" $RED
        exit 1
    }
    
    print_msg "🚀 启动Flask应用(前台模式，显示详细日志)..." $BLUE
    print_msg "💡 你将看到所有请求的详细处理日志" $CYAN
    print_msg "📋 包括: 请求解析、飞书API调用、图片生成等步骤\n" $YELLOW
    
    # 使用前台模式启动，添加Python无缓冲输出确保日志实时显示
    PYTHONUNBUFFERED=1 .venv/bin/python app.py
}

# ngrok隧道模式
run_ngrok() {
    print_header "ngrok稳定隧道模式"
    
    # 清理可能的进程冲突
    cleanup_conflicting_processes || {
        print_msg "❌ 进程清理失败，无法启动服务" $RED
        exit 1
    }
    
    # 检查ngrok是否安装
    if ! command -v ngrok &> /dev/null; then
        print_msg "❌ ngrok未安装" $RED
        print_msg "安装方法: npm install -g @ngrok/ngrok" $YELLOW
        print_msg "或运行: ./setup_ngrok.sh" $CYAN
        exit 1
    fi
    
    # 检查ngrok是否已配置认证
    if ! ngrok config check &>/dev/null; then
        print_msg "❌ ngrok未配置认证token" $RED
        print_msg "请运行: ./setup_ngrok.sh 进行配置" $YELLOW
        print_msg "或手动运行: ngrok config add-authtoken <your-token>" $CYAN
        exit 1
    fi
    
    print_msg "🚀 启动Flask应用(后台模式，日志输出到文件)..." $BLUE
    print_msg "💡 实时查看详细日志: tail -f flask.log" $CYAN
    
    # 使用后台模式启动，但将日志输出到文件便于查看
    PYTHONUNBUFFERED=1 .venv/bin/python app.py > flask.log 2>&1 &
    FLASK_PID=$!
    
    if ! check_service; then
        print_msg "❌ Flask应用启动失败，查看日志:" $RED
        if [ -f "flask.log" ]; then
            tail -20 flask.log
        fi
        cleanup
        exit 1
    fi
    
    print_msg "🌐 启动ngrok稳定隧道..." $BLUE
    print_msg "⏳ 正在建立隧道连接..." $YELLOW
    
    # 启动ngrok
    ngrok http --log=stdout --region=ap 3000 &
    TUNNEL_PID=$!
    
    sleep 5
    
    # 尝试获取ngrok URL
    NGROK_URL=""
    for i in {1..10}; do
        if command -v curl &> /dev/null; then
            NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok\.io' | head -1 || echo "")
            if [[ -n "$NGROK_URL" ]]; then
                break
            fi
        fi
        sleep 1
    done
    
    print_msg "\n🎉 ngrok隧道已启动！" $GREEN
    print_msg "📍 配置信息:" $CYAN
    echo "  - 本地地址: http://localhost:3000"
    echo "  - Web控制台: http://localhost:4040"
    if [[ -n "$NGROK_URL" ]]; then
        echo "  - 公网地址: $NGROK_URL"
        echo "  - Webhook地址: $NGROK_URL/hook"
    else
        echo "  - 公网地址: 请查看上方ngrok输出或访问 http://localhost:4040"
        echo "  - Webhook地址: https://你的域名.ngrok.io/hook"
    fi
    
    print_msg "\n📋 日志查看:" $PURPLE
    echo "  - 实时Flask日志: tail -f flask.log"
    echo "  - ngrok连接日志: 显示在上方终端"
    echo "  - 详细请求日志: 包含JSON解析、飞书API调用等"
    
    print_msg "\n✨ ngrok优势:" $GREEN
    echo "  ✅ 稳定性高，自动重连"
    echo "  ✅ 支持HTTPS和Web控制台" 
    echo "  ✅ 请求检查和重放功能"
    echo "  ✅ 比localtunnel稳定90%"
    
    show_test_options
    
    print_msg "\n按 Ctrl+C 停止所有服务" $CYAN
    
    # 等待进程
    wait $FLASK_PID $TUNNEL_PID
}

# localtunnel隧道模式（备用）
run_localtunnel() {
    print_header "localtunnel备用隧道模式"
    
    # 清理可能的进程冲突
    cleanup_conflicting_processes || {
        print_msg "❌ 进程清理失败，无法启动服务" $RED
        exit 1
    }
    
    # 检查localtunnel是否安装
    if ! command -v lt &> /dev/null; then
        print_msg "❌ localtunnel未安装" $RED
        print_msg "安装方法: npm install -g localtunnel" $YELLOW
        exit 1
    fi
    
    print_msg "⚠️ 注意: localtunnel稳定性较差，建议优先使用ngrok" $YELLOW
    
    print_msg "🚀 启动Flask应用(后台模式，日志输出到文件)..." $BLUE
    print_msg "💡 实时查看详细日志: tail -f flask.log" $CYAN
    
    # 使用后台模式启动，但将日志输出到文件便于查看
    PYTHONUNBUFFERED=1 .venv/bin/python app.py > flask.log 2>&1 &
    FLASK_PID=$!
    
    if ! check_service; then
        print_msg "❌ Flask应用启动失败，查看日志:" $RED
        if [ -f "flask.log" ]; then
            tail -20 flask.log
        fi
        cleanup
        exit 1
    fi
    
    print_msg "🌐 启动localtunnel内网穿透..." $BLUE
    print_msg "⏳ 正在获取公网地址..." $YELLOW
    
    # 启动localtunnel并获取URL
    lt --port 3000 &
    TUNNEL_PID=$!
    
    sleep 3
    
    print_msg "\n🎉 localtunnel服务已启动！" $GREEN
    print_msg "📍 配置信息:" $CYAN
    echo "  - 本地地址: http://localhost:3000"
    echo "  - 公网地址: 请查看上方localtunnel输出"
    echo "  - Webhook地址: https://你的域名.loca.lt/hook"
    
    print_msg "\n📋 日志查看:" $PURPLE
    echo "  - 实时Flask日志: tail -f flask.log"
    echo "  - localtunnel连接日志: 显示在上方终端"
    echo "  - 详细请求日志: 包含JSON解析、飞书API调用等"
    
    print_msg "\n⚠️ 重要提示:" $YELLOW  
    echo "  1. 复制上方显示的公网地址"
    echo "  2. 在飞书webhook配置中使用: https://域名.loca.lt/hook"
    echo "  3. localtunnel经常断线，如遇503错误请重启"
    echo "  4. 建议升级到ngrok获得更好体验"
    
    show_test_options
    
    print_msg "\n按 Ctrl+C 停止所有服务" $CYAN
    
    # 等待进程
    wait $FLASK_PID $TUNNEL_PID
}

# 显示帮助信息
show_help() {
    print_msg "🏠 飞书名片生成器 - 启动脚本 v2.2" $PURPLE
    echo "使用方法: ./start.sh [选项]"
    echo
    echo "选项:"
    echo "  1, ngrok      - ngrok隧道模式 (稳定推荐) ⭐⭐⭐⭐"
    echo "  2, tunnel     - localtunnel隧道模式 (免费备用) ⭐⭐"
    echo "  3, local      - 本地开发模式 (仅本地测试)"
    echo "  -h, --help    - 显示此帮助信息"
    echo
    echo "系统要求:"
    echo "  - Python 3.9 - 3.13 (完全支持Python 3.13)"
    echo "  - 基础工具: curl"
    echo "  - macOS: Xcode Command Line Tools (Pillow编译)"
    echo "  - Linux: gcc, python3-dev, python3-venv"
    echo
    echo "功能特性:"
    echo "  - 🔍 智能系统依赖检查"
    echo "  - 📦 自动设置Python虚拟环境和依赖"
    echo "  - 🚀 Python 3.13优化支持"
    echo "  - 🌐 ngrok模式: 稳定的HTTPS隧道 + Web控制台"
    echo "  - 🌍 localtunnel模式: 免费但不稳定的隧道"
    echo "  - 🏠 本地模式: 仅在localhost:3000运行"
    echo "  - ⚡ 智能服务检测和错误诊断"
    echo
    echo "隧道工具对比:"
    echo "  ngrok     - 稳定性95%+, 自动重连, Web界面, HTTPS"
    echo "  localtunnel - 稳定性60%, 经常503错误, 免费"
    echo
    echo "配置工具:"
    echo "  ./setup_ngrok.sh    - 配置ngrok认证token"
    echo
    echo "测试工具:"
    echo "  ./local_test.py     - Python完整测试套件" 
    echo "  ./batch_test.sh     - 批量自动化测试"
    echo "  test_page.html      - 可视化测试界面"
    echo
    echo "故障排除:"
    echo "  1. Pillow安装失败 → 安装编译工具或使用预编译wheel"
    echo "  2. 虚拟环境创建失败 → 安装python3-venv"
    echo "  3. 依赖版本冲突 → 删除.venv目录重新创建"
    echo "  4. Python版本不支持 → 使用Python 3.9-3.13"
}

# 主函数
main() {
    print_msg "🏠 飞书名片生成器启动工具" $PURPLE
    print_msg "版本: 2.2 | Python 3.13优化 + 智能依赖检查" $CYAN
    
    # 检查参数
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        1|ngrok)
            choice="1"
            ;;
        2|tunnel|localtunnel)
            choice="2"
            ;;
        3|local)
            choice="3"
            ;;
        "")
            # 交互式选择
            ;;
        *)
            print_msg "❌ 无效参数: $1" $RED
            show_help
            exit 1
            ;;
    esac
    
    # 基础检查
    check_system_dependencies
    check_python
    setup_venv
    setup_env
    
    # 如果没有预设选择，则询问用户
    if [[ -z "${choice:-}" ]]; then
        print_header "选择运行模式"
        print_msg "1) ngrok隧道 - 稳定推荐 ⭐⭐⭐⭐" $GREEN
        print_msg "2) localtunnel隧道 - 免费备用 ⭐⭐" $YELLOW
        print_msg "3) 本地开发模式 - 仅本地测试" $BLUE
        echo
        print_msg "💡 推荐: 选择1(ngrok)获得更稳定的隧道服务" $CYAN
        read -p "请输入选项 (1, 2 或 3): " choice
    fi
    
    case $choice in
        1)
            run_ngrok
            ;;
        2)
            run_localtunnel
            ;;
        3)
            run_local
            ;;
        *)
            print_msg "⚠️ 无效选项，启动本地模式" $YELLOW
            run_local
            ;;
    esac
}

# 执行主函数
main "$@"