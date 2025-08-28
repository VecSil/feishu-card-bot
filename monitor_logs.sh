#!/bin/bash
# Flask日志监控和分析工具
# 用于实时查看和分析Flask应用的详细日志

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 显示帮助信息
show_help() {
    print_msg "📋 Flask日志监控工具" $PURPLE
    echo "用法: ./monitor_logs.sh [选项]"
    echo
    echo "选项:"
    echo "  1, tail    - 实时查看Flask日志 (默认)"
    echo "  2, filter  - 过滤显示特定类型日志"
    echo "  3, errors  - 只显示错误和警告"
    echo "  4, requests - 只显示HTTP请求日志"
    echo "  5, analyze - 分析日志统计信息"
    echo "  -h, --help - 显示此帮助信息"
    echo
    echo "实时查看示例:"
    echo "  ./monitor_logs.sh          # 查看所有日志"
    echo "  ./monitor_logs.sh errors   # 只看错误"
    echo "  ./monitor_logs.sh requests # 只看请求"
}

# 检查日志文件是否存在
check_log_file() {
    if [ ! -f "flask.log" ]; then
        print_msg "❌ flask.log文件不存在" $RED
        print_msg "请先启动Flask应用: ./start.sh" $YELLOW
        exit 1
    fi
}

# 实时查看所有日志
tail_logs() {
    print_header "实时Flask日志 (Ctrl+C退出)"
    print_msg "📋 包含所有详细日志: 请求解析、飞书API、图片生成等" $CYAN
    echo
    tail -f flask.log
}

# 过滤特定类型日志
filter_logs() {
    print_header "过滤日志查看"
    print_msg "选择要查看的日志类型:" $CYAN
    echo "1) 🔍 请求信息 (收到请求、解析数据)"
    echo "2) 🔑 飞书API (Token获取、API调用)" 
    echo "3) 📊 图片处理 (生成、上传)"
    echo "4) ❌ 错误信息 (异常、失败)"
    echo "5) ✅ 成功信息 (处理完成)"
    
    read -p "请选择 (1-5): " filter_choice
    
    case $filter_choice in
        1)
            print_msg "🔍 显示请求相关日志:" $BLUE
            tail -f flask.log | grep -E "(收到请求|解析.*数据|payload)"
            ;;
        2) 
            print_msg "🔑 显示飞书API相关日志:" $BLUE
            tail -f flask.log | grep -E "(Token|API|飞书|feishu)"
            ;;
        3)
            print_msg "📊 显示图片处理相关日志:" $BLUE  
            tail -f flask.log | grep -E "(图片|image|生成|上传|PNG)"
            ;;
        4)
            print_msg "❌ 显示错误相关日志:" $RED
            tail -f flask.log | grep -E "(ERROR|❌|失败|异常|Exception)"
            ;;
        5)
            print_msg "✅ 显示成功相关日志:" $GREEN
            tail -f flask.log | grep -E "(✅|成功|SUCCESS|完成)"
            ;;
        *)
            print_msg "无效选择，显示所有日志" $YELLOW
            tail_logs
            ;;
    esac
}

# 只显示错误
show_errors() {
    print_header "错误和警告日志"
    print_msg "🚨 实时显示错误、异常和警告信息" $RED
    echo
    tail -f flask.log | grep -E "(ERROR|WARNING|❌|⚠️|失败|异常|Exception|Traceback)"
}

# 只显示请求日志  
show_requests() {
    print_header "HTTP请求日志"
    print_msg "🌐 实时显示所有HTTP请求和响应" $BLUE
    echo
    tail -f flask.log | grep -E "(收到请求|POST|GET|HTTP|🔍|📋|🎯)"
}

# 分析日志统计
analyze_logs() {
    print_header "日志统计分析"
    
    if [ ! -f "flask.log" ]; then
        check_log_file
        return
    fi
    
    echo "📊 日志文件信息:"
    echo "  - 文件大小: $(du -h flask.log | cut -f1)"
    echo "  - 总行数: $(wc -l < flask.log)"
    echo "  - 最后修改: $(stat -f %Sm flask.log 2>/dev/null || stat -c %y flask.log)"
    echo
    
    echo "📈 请求统计:"
    local post_count=$(grep -c "POST.*hook" flask.log 2>/dev/null || echo "0")
    local get_count=$(grep -c "GET.*" flask.log 2>/dev/null || echo "0")
    echo "  - POST请求: $post_count 次"
    echo "  - GET请求: $get_count 次"
    echo
    
    echo "🔍 处理状态:"
    local success_count=$(grep -c "✅" flask.log 2>/dev/null || echo "0")
    local error_count=$(grep -c "❌" flask.log 2>/dev/null || echo "0") 
    local warning_count=$(grep -c "⚠️" flask.log 2>/dev/null || echo "0")
    echo "  - 成功处理: $success_count 次"
    echo "  - 错误处理: $error_count 次"
    echo "  - 警告信息: $warning_count 次"
    echo
    
    echo "🎯 最近5条日志:"
    tail -5 flask.log | while read line; do
        echo "  $(date '+%H:%M:%S') | $line"
    done
    
    echo
    print_msg "💡 使用 './monitor_logs.sh tail' 实时查看新日志" $CYAN
}

# 主函数
main() {
    case "${1:-tail}" in
        -h|--help)
            show_help
            ;;
        1|tail)
            check_log_file
            tail_logs
            ;;
        2|filter)
            check_log_file
            filter_logs
            ;;
        3|errors)
            check_log_file
            show_errors
            ;;
        4|requests)
            check_log_file
            show_requests
            ;;
        5|analyze)
            analyze_logs
            ;;
        *)
            if [ -f "flask.log" ]; then
                tail_logs
            else
                show_help
                echo
                check_log_file
            fi
            ;;
    esac
}

# 执行主函数
main "$@"