#!/bin/bash
# ngrok监控和自动重启脚本
# 适用于线下活动的稳定性保障

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() {
    echo -e "${2}$(date '+%H:%M:%S') ${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 配置参数
CHECK_INTERVAL=30          # 检查间隔（秒）
RESTART_DELAY=5           # 重启延迟（秒）
MAX_RESTART_ATTEMPTS=3    # 最大重启尝试次数
CURRENT_URL_FILE="current_ngrok_url.txt"
LOG_FILE="ngrok_monitor.log"

# 全局变量
FLASK_PID=""
NGROK_PID=""
RESTART_COUNT=0
LAST_RESTART_TIME=0

# 信号处理
cleanup() {
    print_msg "\n🛑 收到停止信号，正在清理..." $YELLOW
    
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        kill "$FLASK_PID"
        print_msg "✅ Flask进程已终止 (PID: $FLASK_PID)" $GREEN
    fi
    
    if [[ -n "$NGROK_PID" ]] && kill -0 "$NGROK_PID" 2>/dev/null; then
        kill "$NGROK_PID"
        print_msg "✅ ngrok进程已终止 (PID: $NGROK_PID)" $GREEN
    fi
    
    # 清理文件
    rm -f "$CURRENT_URL_FILE" 2>/dev/null || true
    
    print_msg "👋 监控脚本已停止" $CYAN
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# 检查依赖
check_dependencies() {
    print_header "检查系统依赖"
    
    if ! command -v ngrok &> /dev/null; then
        print_msg "❌ ngrok未安装" $RED
        print_msg "请运行: ./setup_ngrok.sh" $YELLOW
        exit 1
    fi
    
    if ! ngrok config check &>/dev/null; then
        print_msg "❌ ngrok未配置认证token" $RED
        print_msg "请运行: ./setup_ngrok.sh" $YELLOW
        exit 1
    fi
    
    if [[ ! -d ".venv" ]]; then
        print_msg "❌ Python虚拟环境不存在" $RED
        print_msg "请先运行: ./start.sh" $YELLOW
        exit 1
    fi
    
    print_msg "✅ 系统依赖检查通过" $GREEN
}

# 启动服务
start_services() {
    local attempt=${1:-1}
    print_header "启动服务 (尝试 $attempt)"
    
    # 清理旧进程
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        kill "$FLASK_PID" 2>/dev/null || true
        sleep 2
    fi
    
    if [[ -n "$NGROK_PID" ]] && kill -0 "$NGROK_PID" 2>/dev/null; then
        kill "$NGROK_PID" 2>/dev/null || true
        sleep 2
    fi
    
    # 启动Flask应用
    print_msg "🚀 启动Flask应用..." $BLUE
    .venv/bin/python app.py >> "$LOG_FILE" 2>&1 &
    FLASK_PID=$!
    
    # 等待Flask启动
    print_msg "⏳ 等待Flask服务启动..." $YELLOW
    local flask_ready=false
    for i in {1..15}; do
        if curl -s http://localhost:3000/healthz > /dev/null 2>&1; then
            flask_ready=true
            break
        fi
        sleep 1
    done
    
    if ! $flask_ready; then
        print_msg "❌ Flask服务启动失败" $RED
        return 1
    fi
    
    print_msg "✅ Flask服务启动成功 (PID: $FLASK_PID)" $GREEN
    
    # 启动ngrok隧道
    print_msg "🌐 启动ngrok隧道..." $BLUE
    ngrok http --log=stdout --log-level=info --region=ap 3000 >> "$LOG_FILE" 2>&1 &
    NGROK_PID=$!
    
    # 等待ngrok启动并获取URL
    print_msg "⏳ 等待ngrok隧道建立..." $YELLOW
    local ngrok_url=""
    for i in {1..20}; do
        if ngrok_url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok\.io' | head -1); then
            if [[ -n "$ngrok_url" ]]; then
                break
            fi
        fi
        sleep 1
    done
    
    if [[ -z "$ngrok_url" ]]; then
        print_msg "❌ ngrok隧道建立失败" $RED
        return 1
    fi
    
    # 保存当前URL
    echo "$ngrok_url" > "$CURRENT_URL_FILE"
    
    print_msg "✅ ngrok隧道建立成功 (PID: $NGROK_PID)" $GREEN
    print_msg "🌐 公网地址: $ngrok_url" $CYAN
    print_msg "🔗 Webhook地址: ${ngrok_url}/hook" $CYAN
    print_msg "📊 Web控制台: http://localhost:4040" $CYAN
    
    # 记录启动时间
    LAST_RESTART_TIME=$(date +%s)
    RESTART_COUNT=$attempt
    
    return 0
}

# 检查服务状态
check_service_health() {
    local current_url=""
    
    # 检查Flask服务
    if ! curl -s http://localhost:3000/healthz > /dev/null 2>&1; then
        print_msg "❌ Flask服务异常" $RED
        return 1
    fi
    
    # 检查ngrok进程
    if ! kill -0 "$NGROK_PID" 2>/dev/null; then
        print_msg "❌ ngrok进程已停止" $RED
        return 1
    fi
    
    # 检查ngrok隧道
    if [[ -f "$CURRENT_URL_FILE" ]]; then
        current_url=$(cat "$CURRENT_URL_FILE")
        if ! curl -s "${current_url}/healthz" > /dev/null 2>&1; then
            print_msg "❌ ngrok隧道不可访问: $current_url" $RED
            return 1
        fi
    else
        print_msg "⚠️ 当前URL文件不存在" $YELLOW
        return 1
    fi
    
    return 0
}

# 重启服务
restart_services() {
    local current_time=$(date +%s)
    local time_since_last=$((current_time - LAST_RESTART_TIME))
    
    print_msg "🔄 准备重启服务..." $YELLOW
    
    # 防止频繁重启（至少间隔60秒）
    if [[ $time_since_last -lt 60 ]]; then
        print_msg "⏰ 距离上次重启仅${time_since_last}秒，等待中..." $YELLOW
        sleep $((60 - time_since_last))
    fi
    
    # 检查重启次数限制
    if [[ $RESTART_COUNT -ge $MAX_RESTART_ATTEMPTS ]]; then
        print_msg "❌ 达到最大重启次数限制 ($MAX_RESTART_ATTEMPTS)" $RED
        print_msg "⚠️ 请手动检查系统状态" $YELLOW
        print_msg "💡 建议检查网络连接和ngrok配置" $CYAN
        
        # 重置计数器（等待更长时间）
        print_msg "⏳ 等待5分钟后重置重启计数器..." $YELLOW
        sleep 300
        RESTART_COUNT=0
    fi
    
    sleep $RESTART_DELAY
    
    if start_services $((RESTART_COUNT + 1)); then
        print_msg "✅ 服务重启成功" $GREEN
        
        # 通知用户更新webhook URL
        if [[ -f "$CURRENT_URL_FILE" ]]; then
            local new_url=$(cat "$CURRENT_URL_FILE")
            print_msg "📢 重要: 请更新飞书webhook地址为: ${new_url}/hook" $PURPLE
        fi
        
        return 0
    else
        print_msg "❌ 服务重启失败" $RED
        return 1
    fi
}

# 显示状态报告
show_status() {
    print_header "服务状态报告"
    
    local uptime_minutes=$((($( date +%s) - LAST_RESTART_TIME) / 60))
    
    echo "📊 运行统计:"
    echo "  - 启动时间: $(date -r $LAST_RESTART_TIME '+%Y-%m-%d %H:%M:%S')"
    echo "  - 运行时长: ${uptime_minutes} 分钟"
    echo "  - 重启次数: $RESTART_COUNT"
    
    if [[ -f "$CURRENT_URL_FILE" ]]; then
        local current_url=$(cat "$CURRENT_URL_FILE")
        echo
        echo "🌐 访问信息:"
        echo "  - 本地地址: http://localhost:3000"
        echo "  - 公网地址: $current_url"
        echo "  - Webhook地址: ${current_url}/hook"
        echo "  - Web控制台: http://localhost:4040"
    fi
    
    echo
    echo "📈 进程状态:"
    echo "  - Flask PID: $FLASK_PID ($(kill -0 "$FLASK_PID" 2>/dev/null && echo "运行中" || echo "已停止"))"
    echo "  - ngrok PID: $NGROK_PID ($(kill -0 "$NGROK_PID" 2>/dev/null && echo "运行中" || echo "已停止"))"
}

# 主监控循环
monitor_loop() {
    print_header "开始监控循环"
    print_msg "📊 检查间隔: ${CHECK_INTERVAL}秒" $CYAN
    print_msg "🔄 最大重启次数: $MAX_RESTART_ATTEMPTS" $CYAN
    print_msg "📝 日志文件: $LOG_FILE" $CYAN
    echo
    
    local check_count=0
    
    while true; do
        check_count=$((check_count + 1))
        
        # 每10次检查显示一次状态报告
        if [[ $((check_count % 10)) -eq 0 ]]; then
            show_status
            echo
        fi
        
        if check_service_health; then
            print_msg "✅ 服务运行正常" $GREEN
        else
            print_msg "⚠️ 服务异常，准备重启..." $YELLOW
            
            if restart_services; then
                print_msg "🎉 服务恢复正常" $GREEN
            else
                print_msg "❌ 服务重启失败，将在下次循环重试" $RED
            fi
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# 主函数
main() {
    print_header "ngrok稳定性监控脚本"
    print_msg "🔍 用于线下活动的自动故障恢复" $PURPLE
    
    # 创建日志文件
    echo "$(date): ngrok监控脚本启动" > "$LOG_FILE"
    
    # 检查依赖
    check_dependencies
    
    # 首次启动服务
    if start_services 1; then
        print_msg "🎉 初始化成功，开始监控..." $GREEN
        echo
        print_msg "💡 提示: 按 Ctrl+C 停止监控" $CYAN
        
        # 开始监控
        monitor_loop
    else
        print_msg "❌ 初始化失败，请检查配置" $RED
        exit 1
    fi
}

# 启动主函数
main "$@"