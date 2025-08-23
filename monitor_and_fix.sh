#!/bin/bash
# ngrok URL监控和自动修复脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 配置参数
CHECK_INTERVAL=${CHECK_INTERVAL:-30}  # 检查间隔(秒)
MAX_RETRIES=${MAX_RETRIES:-3}        # 最大重试次数

print_header "🔄 ngrok URL监控服务启动"
print_msg "⏰ 检查间隔: ${CHECK_INTERVAL}秒" $BLUE
print_msg "🔄 最大重试: ${MAX_RETRIES}次" $BLUE
echo

retry_count=0

while true; do
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    print_msg "[$current_time] 🔍 检查服务状态..." $BLUE
    
    # 获取当前ngrok URL
    CURRENT_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)
    
    if [[ -z "$CURRENT_URL" ]]; then
        print_msg "❌ ngrok未运行" $RED
        ((retry_count++))
        
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            print_msg "🚨 ngrok连续失败${MAX_RETRIES}次，需要手动检查" $RED
            print_msg "💡 建议操作:" $YELLOW
            echo "  1. 检查ngrok进程: ps aux | grep ngrok"
            echo "  2. 重启ngrok: ngrok http 3000"
            echo "  3. 重新运行监控: ./monitor_and_fix.sh"
            exit 1
        fi
        
        print_msg "⏳ 等待ngrok恢复... (${retry_count}/${MAX_RETRIES})" $YELLOW
        sleep $CHECK_INTERVAL
        continue
    fi
    
    # 重置重试计数
    retry_count=0
    
    # 检查URL是否有变更
    PREVIOUS_URL=""
    if [[ -f ".previous_ngrok_url" ]]; then
        PREVIOUS_URL=$(cat .previous_ngrok_url 2>/dev/null)
    fi
    
    # URL变更检测
    if [[ "$CURRENT_URL" != "$PREVIOUS_URL" ]]; then
        print_msg "🔄 检测到URL变更!" $YELLOW
        echo "  旧地址: ${PREVIOUS_URL:-'无'}"
        echo "  新地址: $CURRENT_URL"
        
        # 测试新URL
        print_msg "🧪 测试新URL..." $BLUE
        HEALTH_CHECK=$(curl -s "$CURRENT_URL/healthz" 2>/dev/null)
        
        if echo "$HEALTH_CHECK" | grep -q "ok"; then
            print_msg "✅ 新URL测试通过" $GREEN
            
            # 保存新URL
            echo "$CURRENT_URL" > .previous_ngrok_url
            echo "$CURRENT_URL" > .current_ngrok_url
            
            # 发出通知
            print_msg "📢 需要更新飞书Webhook配置!" $CYAN
            echo "  新Webhook地址: $CURRENT_URL/hook"
            echo
            
            # 可选：发送通知（如果配置了）
            if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
                curl -s -X POST "$NOTIFICATION_WEBHOOK" \
                    -H "Content-Type: application/json" \
                    -d "{\"text\":\"ngrok URL已更新: $CURRENT_URL/hook\"}" \
                    > /dev/null 2>&1
            fi
            
        else
            print_msg "❌ 新URL测试失败" $RED
            print_msg "⏳ 等待服务就绪..." $YELLOW
        fi
    else
        # URL未变更，进行常规健康检查
        HEALTH_CHECK=$(curl -s "$CURRENT_URL/healthz" 2>/dev/null)
        
        if echo "$HEALTH_CHECK" | grep -q "ok"; then
            print_msg "✅ 服务运行正常 - $CURRENT_URL" $GREEN
        else
            print_msg "⚠️ 服务健康检查失败" $YELLOW
        fi
    fi
    
    # 等待下次检查
    sleep $CHECK_INTERVAL
done