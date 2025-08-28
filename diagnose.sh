#!/bin/bash
# Flask应用快速诊断工具
# 检查常见问题并提供解决方案

# 颜色定义  
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 检查Flask服务状态
check_flask_service() {
    print_header "Flask服务状态检查"
    
    # 检查进程是否运行
    local flask_pids=$(pgrep -f "python.*app.py")
    if [ -n "$flask_pids" ]; then
        print_msg "✅ Flask进程运行中 (PID: $flask_pids)" $GREEN
        
        # 检查端口是否监听
        if lsof -i :3000 &>/dev/null; then
            print_msg "✅ 端口3000正在监听" $GREEN
            
            # 检查健康状态
            if curl -s http://localhost:3000/healthz &>/dev/null; then
                print_msg "✅ 服务健康检查通过" $GREEN
                return 0
            else
                print_msg "❌ 健康检查失败" $RED
                print_msg "💡 尝试: curl http://localhost:3000/healthz" $YELLOW
            fi
        else
            print_msg "❌ 端口3000未监听" $RED
        fi
    else
        print_msg "❌ Flask进程未运行" $RED
        print_msg "💡 启动方法: ./start.sh 3" $YELLOW
    fi
    
    return 1
}

# 检查ngrok状态
check_ngrok_status() {
    print_header "ngrok状态检查"
    
    local ngrok_pids=$(pgrep -f "ngrok")
    if [ -n "$ngrok_pids" ]; then
        print_msg "✅ ngrok进程运行中 (PID: $ngrok_pids)" $GREEN
        
        # 尝试获取隧道URL
        if command -v curl &>/dev/null; then
            local ngrok_url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok\.io' | head -1)
            if [ -n "$ngrok_url" ]; then
                print_msg "🌐 隧道URL: $ngrok_url" $CYAN
                print_msg "🔗 Webhook地址: $ngrok_url/hook" $CYAN
            else
                print_msg "⚠️ 无法获取隧道URL，访问 http://localhost:4040" $YELLOW
            fi
        fi
    else
        print_msg "❌ ngrok进程未运行" $RED
        print_msg "💡 启动方法: ./start.sh 1" $YELLOW
    fi
}

# 检查环境配置
check_environment() {
    print_header "环境配置检查"
    
    # 检查虚拟环境
    if [ -d ".venv" ]; then
        print_msg "✅ 虚拟环境存在" $GREEN
        
        if [ -f ".venv/bin/python" ]; then
            local python_version=$(.venv/bin/python --version 2>&1)
            print_msg "✅ Python版本: $python_version" $GREEN
        else
            print_msg "❌ 虚拟环境损坏" $RED
            print_msg "💡 重新创建: rm -rf .venv && ./start.sh" $YELLOW
        fi
    else
        print_msg "❌ 虚拟环境不存在" $RED
        print_msg "💡 创建环境: ./start.sh" $YELLOW
    fi
    
    # 检查配置文件
    if [ -f ".env" ]; then
        print_msg "✅ .env配置文件存在" $GREEN
        
        # 检查关键配置
        if grep -q "FEISHU_APP_ID=" .env && [ "$(grep FEISHU_APP_ID= .env | cut -d= -f2)" != "" ]; then
            print_msg "✅ 飞书APP_ID已配置" $GREEN
        else
            print_msg "⚠️ 飞书APP_ID未配置" $YELLOW
        fi
        
        if grep -q "FEISHU_APP_SECRET=" .env && [ "$(grep FEISHU_APP_SECRET= .env | cut -d= -f2)" != "" ]; then
            print_msg "✅ 飞书APP_SECRET已配置" $GREEN  
        else
            print_msg "⚠️ 飞书APP_SECRET未配置" $YELLOW
        fi
    else
        print_msg "❌ .env配置文件不存在" $RED
        print_msg "💡 创建配置: cp .env.example .env" $YELLOW
    fi
}

# 检查依赖包
check_dependencies() {
    print_header "依赖包检查"
    
    if [ ! -d ".venv" ]; then
        print_msg "❌ 虚拟环境不存在，跳过依赖检查" $RED
        return 1
    fi
    
    local missing_packages=()
    local required_packages=("flask" "requests" "Pillow" "qrcode" "python-dotenv")
    
    for package in "${required_packages[@]}"; do
        if .venv/bin/pip show "$package" &>/dev/null; then
            local version=$(.venv/bin/pip show "$package" | grep Version | cut -d: -f2 | xargs)
            print_msg "✅ $package: $version" $GREEN
        else
            print_msg "❌ $package 未安装" $RED
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_msg "\n💡 安装缺失包: .venv/bin/pip install ${missing_packages[*]}" $YELLOW
    fi
}

# 测试核心功能
test_core_functionality() {
    print_header "核心功能测试"
    
    if ! check_flask_service; then
        print_msg "❌ Flask服务未运行，无法测试功能" $RED
        return 1
    fi
    
    print_msg "📋 测试健康检查接口..." $BLUE
    local health_response=$(curl -s http://localhost:3000/healthz)
    if [ $? -eq 0 ]; then
        print_msg "✅ 健康检查: $health_response" $GREEN
    else
        print_msg "❌ 健康检查失败" $RED
    fi
    
    print_msg "\n📋 测试POST接口..." $BLUE
    local test_payload='{"nickname":"诊断测试","gender":"未知","profession":"测试","interests":"自动化测试","mbti":"INFP","introduction":"系统诊断测试","wechatQrAttachmentId":""}'
    local post_response=$(curl -s -X POST http://localhost:3000/hook -H "Content-Type: application/json" -d "$test_payload")
    
    if [ $? -eq 0 ]; then
        if echo "$post_response" | grep -q '"status": "ok"'; then
            print_msg "✅ POST接口测试成功" $GREEN
            local image_url=$(echo "$post_response" | grep -o '"image_url": *"[^"]*"' | cut -d'"' -f4)
            if [ -n "$image_url" ]; then
                print_msg "🖼️ 生成的图片: $image_url" $CYAN
            fi
        else
            print_msg "❌ POST接口返回错误" $RED
            echo "响应: $post_response" | head -3
        fi
    else
        print_msg "❌ POST接口测试失败" $RED
    fi
}

# 分析最近的错误
analyze_recent_errors() {
    print_header "最近错误分析"
    
    if [ ! -f "flask.log" ]; then
        print_msg "📋 flask.log文件不存在，无法分析错误" $YELLOW
        return
    fi
    
    print_msg "🔍 分析最近的错误和警告..." $BLUE
    
    # 查找最近的错误
    local recent_errors=$(tail -100 flask.log | grep -E "(ERROR|❌|Exception|Traceback)" | tail -5)
    if [ -n "$recent_errors" ]; then
        print_msg "🚨 发现最近错误:" $RED
        echo "$recent_errors" | while read line; do
            echo "  $line"
        done
        
        # 分析常见错误模式
        if echo "$recent_errors" | grep -q "403"; then
            print_msg "\n💡 403错误解决方案:" $CYAN
            echo "  1. 检查飞书应用权限配置"
            echo "  2. 访问 https://open.feishu.cn/app/ 添加必要权限"
            echo "  3. 重新发布应用版本"
        fi
        
        if echo "$recent_errors" | grep -q "404"; then
            print_msg "\n💡 404错误解决方案:" $CYAN  
            echo "  1. 检查attachment_id是否有效"
            echo "  2. 确认文件未被删除"
            echo "  3. 验证API调用路径正确"
        fi
        
        if echo "$recent_errors" | grep -q "Connection"; then
            print_msg "\n💡 连接错误解决方案:" $CYAN
            echo "  1. 检查网络连接"
            echo "  2. 验证飞书API域名可访问"
            echo "  3. 检查防火墙设置"
        fi
    else
        print_msg "✅ 未发现最近错误" $GREEN
    fi
}

# 生成诊断报告
generate_report() {
    print_header "生成诊断报告"
    
    local report_file="diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Flask应用诊断报告"
        echo "生成时间: $(date)"
        echo "========================="
        echo
        
        echo "系统信息:"
        echo "- 操作系统: $(uname -s)"
        echo "- Python版本: $(python3 --version 2>&1)"
        echo "- 当前目录: $(pwd)"
        echo
        
        echo "服务状态:"
        if pgrep -f "python.*app.py" &>/dev/null; then
            echo "- Flask: 运行中"
        else
            echo "- Flask: 未运行"
        fi
        
        if pgrep -f "ngrok" &>/dev/null; then
            echo "- ngrok: 运行中"
        else
            echo "- ngrok: 未运行"
        fi
        echo
        
        echo "配置文件:"
        if [ -f ".env" ]; then
            echo "- .env: 存在"
        else
            echo "- .env: 不存在"
        fi
        echo
        
        if [ -f "flask.log" ]; then
            echo "最近日志 (最后10行):"
            tail -10 flask.log
        fi
        
    } > "$report_file"
    
    print_msg "📋 诊断报告已保存到: $report_file" $GREEN
}

# 显示帮助
show_help() {
    print_msg "🏥 Flask应用诊断工具" $PURPLE
    echo "用法: ./diagnose.sh [选项]"
    echo
    echo "选项:"
    echo "  1, full     - 完整诊断 (默认)"
    echo "  2, service  - 只检查服务状态"
    echo "  3, env      - 只检查环境配置" 
    echo "  4, test     - 测试核心功能"
    echo "  5, errors   - 分析最近错误"
    echo "  6, report   - 生成诊断报告"
    echo "  -h, --help  - 显示此帮助"
}

# 完整诊断
full_diagnosis() {
    print_msg "🏥 Flask应用完整诊断" $PURPLE
    print_msg "正在检查所有组件..." $CYAN
    
    check_flask_service
    check_ngrok_status
    check_environment  
    check_dependencies
    test_core_functionality
    analyze_recent_errors
    
    print_msg "\n🎯 诊断完成！" $GREEN
    print_msg "💡 如需生成报告: ./diagnose.sh report" $CYAN
}

# 主函数
main() {
    case "${1:-full}" in
        -h|--help)
            show_help
            ;;
        1|full)
            full_diagnosis
            ;;
        2|service)
            check_flask_service
            check_ngrok_status
            ;;
        3|env)
            check_environment
            check_dependencies
            ;;
        4|test)
            test_core_functionality
            ;;
        5|errors)
            analyze_recent_errors
            ;;
        6|report)
            generate_report
            ;;
        *)
            show_help
            echo
            full_diagnosis
            ;;
    esac
}

# 执行主函数
main "$@"