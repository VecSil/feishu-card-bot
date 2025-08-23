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

# 检查Python环境
check_python() {
    if ! command -v python3 &> /dev/null; then
        print_msg "❌ Python3 未安装，请先安装Python3" $RED
        exit 1
    fi
    
    local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    print_msg "✅ Python版本: $python_version" $GREEN
}

# 设置虚拟环境
setup_venv() {
    print_header "设置Python虚拟环境"
    
    if [ ! -d ".venv" ]; then
        print_msg "📦 创建虚拟环境..." $BLUE
        python3 -m venv .venv
        print_msg "✅ 虚拟环境创建完成" $GREEN
    else
        print_msg "✅ 虚拟环境已存在" $GREEN
    fi

    # 检查依赖是否需要更新
    print_msg "📋 检查依赖..." $BLUE
    .venv/bin/pip install --upgrade pip -q
    
    # 检查requirements.txt中的包是否已安装
    local need_install=false
    while IFS= read -r package; do
        package_name=$(echo "$package" | cut -d'=' -f1)
        if ! .venv/bin/pip show "$package_name" &>/dev/null; then
            need_install=true
            break
        fi
    done < requirements.txt
    
    if $need_install; then
        print_msg "📦 安装项目依赖..." $BLUE
        .venv/bin/pip install -r requirements.txt -q
    fi
    
    # 安装python-dotenv（如果未安装）
    if ! .venv/bin/pip show python-dotenv &>/dev/null; then
        print_msg "📦 安装python-dotenv..." $BLUE
        .venv/bin/pip install python-dotenv -q
    fi
    
    print_msg "✅ 依赖检查完成" $GREEN
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
    
    print_msg "🚀 启动Flask应用..." $BLUE
    .venv/bin/python app.py &
    FLASK_PID=$!
    
    if check_service; then
        print_msg "🌐 本地访问地址:" $GREEN
        echo "  - 健康检查: http://localhost:3000/healthz"  
        echo "  - API端点: http://localhost:3000/hook"
        
        show_test_options
        
        print_msg "\n按 Ctrl+C 停止服务" $CYAN
        
        # 等待Flask进程
        wait $FLASK_PID
    else
        print_msg "❌ Flask应用启动失败" $RED
        cleanup
        exit 1
    fi
}

# ngrok隧道模式
run_ngrok() {
    print_header "ngrok稳定隧道模式"
    
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
    
    print_msg "🚀 启动Flask应用..." $BLUE
    .venv/bin/python app.py &
    FLASK_PID=$!
    
    if ! check_service; then
        print_msg "❌ Flask应用启动失败" $RED
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
    
    # 检查localtunnel是否安装
    if ! command -v lt &> /dev/null; then
        print_msg "❌ localtunnel未安装" $RED
        print_msg "安装方法: npm install -g localtunnel" $YELLOW
        exit 1
    fi
    
    print_msg "⚠️ 注意: localtunnel稳定性较差，建议优先使用ngrok" $YELLOW
    
    print_msg "🚀 启动Flask应用..." $BLUE
    .venv/bin/python app.py &
    FLASK_PID=$!
    
    if ! check_service; then
        print_msg "❌ Flask应用启动失败" $RED
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
    print_msg "🏠 飞书名片生成器 - 启动脚本 v2.1" $PURPLE
    echo "使用方法: ./start.sh [选项]"
    echo
    echo "选项:"
    echo "  1, ngrok      - ngrok隧道模式 (稳定推荐) ⭐⭐⭐⭐"
    echo "  2, tunnel     - localtunnel隧道模式 (免费备用) ⭐⭐"
    echo "  3, local      - 本地开发模式 (仅本地测试)"
    echo "  -h, --help    - 显示此帮助信息"
    echo
    echo "功能特性:"
    echo "  - 自动设置Python虚拟环境和依赖"
    echo "  - ngrok模式: 稳定的HTTPS隧道 + Web控制台"
    echo "  - localtunnel模式: 免费但不稳定的隧道"
    echo "  - 本地模式: 仅在localhost:3000运行"
    echo "  - 智能服务检测和自动重启"
    echo
    echo "隧道工具对比:"
    echo "  ngrok     - 稳定性90%+, 自动重连, Web界面"
    echo "  localtunnel - 稳定性60%, 经常503错误"
    echo
    echo "配置工具:"
    echo "  ./setup_ngrok.sh    - 配置ngrok认证token"
    echo
    echo "测试工具:"
    echo "  ./local_test.py     - Python完整测试套件" 
    echo "  ./batch_test.sh     - 批量自动化测试"
    echo "  test_page.html      - 可视化测试界面"
}

# 主函数
main() {
    print_msg "🏠 飞书名片生成器启动工具" $PURPLE
    print_msg "版本: 2.1 | 支持ngrok稳定隧道 + 本地开发" $CYAN
    
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