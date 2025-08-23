#!/bin/bash
# 批量测试脚本 - 自动化测试飞书名片生成功能
# 使用方式: ./batch_test.sh

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

# 检查依赖
check_dependencies() {
    print_header "检查依赖"
    
    if ! command -v curl &> /dev/null; then
        print_msg "❌ curl 未安装" $RED
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_msg "⚠️ jq 未安装，JSON输出可能不够美观" $YELLOW
        USE_JQ=false
    else
        USE_JQ=true
    fi
    
    print_msg "✅ 依赖检查完成" $GREEN
}

# 检查服务状态
check_service() {
    print_header "检查服务状态"
    
    local health_response
    if health_response=$(curl -s -w "%{http_code}" http://localhost:3000/healthz 2>/dev/null); then
        local http_code=${health_response: -3}
        local response_body=${health_response%???}
        
        if [[ "$http_code" == "200" ]]; then
            print_msg "✅ 服务正常运行 (HTTP $http_code)" $GREEN
            return 0
        else
            print_msg "❌ 服务异常 (HTTP $http_code)" $RED
            return 1
        fi
    else
        print_msg "❌ 无法连接到服务 (localhost:3000)" $RED
        print_msg "请执行以下步骤:" $YELLOW
        echo "  1. 运行: ./start.sh"
        echo "  2. 选择选项2 - 仅本地运行"
        echo "  3. 等待服务启动后重新运行测试"
        return 1
    fi
}

# 格式化JSON输出
format_json() {
    local json_data="$1"
    if $USE_JQ; then
        echo "$json_data" | jq '.'
    else
        echo "$json_data"
    fi
}

# 单个测试用例
test_single_case() {
    local case_name="$1"
    local json_data="$2"
    local test_png="${3:-false}"
    
    print_msg "🧪 测试: $case_name" $BLUE
    
    # JSON 响应测试
    local start_time=$(date +%s%3N)
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST http://localhost:3000/hook \
        -H "Content-Type: application/json" \
        -d "$json_data" 2>/dev/null)
    local end_time=$(date +%s%3N)
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    local duration=$((end_time - start_time))
    
    if [[ "$http_code" == "200" ]]; then
        print_msg "  ✅ JSON响应成功 (${duration}ms)" $GREEN
        
        # 解析关键信息
        if $USE_JQ; then
            local status=$(echo "$response_body" | jq -r '.status // "unknown"')
            local saved_path=$(echo "$response_body" | jq -r '.saved_path // ""')
            local image_key=$(echo "$response_body" | jq -r '.image_key // ""')
            
            if [[ "$status" == "ok" ]]; then
                print_msg "  📄 状态: $status" $GREEN
            else
                print_msg "  ⚠️ 状态: $status" $YELLOW
            fi
            
            if [[ -n "$saved_path" && "$saved_path" != "null" ]]; then
                local filename=$(basename "$saved_path")
                if [[ -f "$saved_path" ]]; then
                    local filesize=$(du -h "$saved_path" | cut -f1)
                    print_msg "  📁 文件已保存: $filename ($filesize)" $GREEN
                else
                    print_msg "  ⚠️ 保存路径不存在: $saved_path" $YELLOW
                fi
            fi
            
            if [[ -n "$image_key" && "$image_key" != "null" ]]; then
                print_msg "  🔑 飞书图片Key: ${image_key:0:20}..." $GREEN
            fi
        else
            # 简单的状态检查（不使用jq）
            if echo "$response_body" | grep -q '"status":"ok"'; then
                print_msg "  📄 响应状态正常" $GREEN
            else
                print_msg "  ⚠️ 响应状态可能异常" $YELLOW
            fi
        fi
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_msg "  ❌ JSON响应失败 (HTTP $http_code)" $RED
        print_msg "  错误详情: $response_body" $RED
        FAILED_CASES+=("$case_name (JSON)")
    fi
    
    # PNG 测试（如果启用）
    if [[ "$test_png" == "true" ]]; then
        print_msg "  🖼️ 测试PNG生成..." $CYAN
        
        local png_response=$(curl -s -w "\n%{http_code}" \
            -X POST "http://localhost:3000/hook?format=png" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2>/dev/null)
        
        local png_http_code=$(echo "$png_response" | tail -n1)
        
        if [[ "$png_http_code" == "200" ]]; then
            local png_data=$(echo "$png_response" | head -n -1)
            local png_size=${#png_data}
            
            if [[ $png_size -gt 1000 ]]; then
                # 保存PNG文件用于验证
                local png_filename="test_${case_name//[[:space:]]/_}.png"
                echo "$png_data" > "$png_filename"
                print_msg "  ✅ PNG生成成功 (~${png_size} bytes)" $GREEN
                PNG_SUCCESS_COUNT=$((PNG_SUCCESS_COUNT + 1))
            else
                print_msg "  ⚠️ PNG数据异常 (size: $png_size)" $YELLOW
            fi
        else
            print_msg "  ❌ PNG生成失败 (HTTP $png_http_code)" $RED
            FAILED_CASES+=("$case_name (PNG)")
        fi
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo
}

# 性能测试
performance_test() {
    print_header "性能测试"
    
    local test_data='{"name":"性能测试用户","email":"perf@test.com"}'
    local total_time=0
    local test_count=5
    
    print_msg "执行 $test_count 次连续请求..." $BLUE
    
    for ((i=1; i<=test_count; i++)); do
        local start_time=$(date +%s%3N)
        local response=$(curl -s -w "%{http_code}" \
            -X POST http://localhost:3000/hook \
            -H "Content-Type: application/json" \
            -d "$test_data" 2>/dev/null)
        local end_time=$(date +%s%3N)
        
        local duration=$((end_time - start_time))
        total_time=$((total_time + duration))
        
        local http_code=${response: -3}
        if [[ "$http_code" == "200" ]]; then
            print_msg "  请求 $i: ${duration}ms ✅" $GREEN
        else
            print_msg "  请求 $i: ${duration}ms ❌ (HTTP $http_code)" $RED
        fi
    done
    
    local avg_time=$((total_time / test_count))
    print_msg "平均响应时间: ${avg_time}ms" $CYAN
    
    if [[ $avg_time -lt 3000 ]]; then
        print_msg "🚀 性能优秀 (< 3秒)" $GREEN
    elif [[ $avg_time -lt 10000 ]]; then
        print_msg "🙂 性能良好 (< 10秒)" $YELLOW
    else
        print_msg "🐌 性能较慢 (> 10秒)" $RED
    fi
    
    echo
}

# 主函数
main() {
    # 初始化计数器
    SUCCESS_COUNT=0
    PNG_SUCCESS_COUNT=0
    TOTAL_TESTS=0
    FAILED_CASES=()
    
    print_msg "🧪 飞书名片生成器 - 批量测试工具" $PURPLE
    print_msg "版本: 1.0 | 测试目标: localhost:3000" $CYAN
    echo
    
    # 检查依赖和服务
    check_dependencies
    if ! check_service; then
        exit 1
    fi
    
    print_header "开始批量测试"
    
    # 测试用例定义
    declare -A test_cases=(
        ["基础测试"]='{"name":"张三","title":"产品经理","company":"创新科技有限公司","phone":"13800138000","email":"zhangsan@company.com"}'
        ["完整信息"]='{"name":"李四","title":"高级工程师","company":"智能科技股份","phone":"13900139000","email":"lisi@tech.com","avatar_url":"https://avatars.githubusercontent.com/u/1?v=4","qrcode_text":"https://github.com/lisi"}'
        ["中文字段"]='{"姓名":"王五","职位":"设计总监","公司":"创意设计工作室","电话":"13700137000","邮箱":"wangwu@design.com"}'
        ["最小数据"]='{"name":"赵六"}'
        ["长文本测试"]='{"name":"钱七","company":"Test Company with Very Long Name That Might Cause Layout Issues","title":"Senior Software Development Engineer with Extended Title","email":"very.long.email@extremely-long-domain.com"}'
        ["特殊字符"]='{"name":"孙八 & Co.","title":"CEO/CTO","company":"Tech@2024","phone":"+86-138-0013-8000","email":"sun8+test@company-name.com"}'
        ["二维码测试"]='{"name":"周九","qrcode_text":"BEGIN:VCARD\nVERSION:3.0\nFN:周九\nEND:VCARD","title":"技术专家"}'
        ["空字段混合"]='{"name":"吴十","title":"","company":"正常公司","phone":"","email":"wu10@company.com","avatar_url":""}'
    )
    
    # 执行测试用例
    for case_name in "${!test_cases[@]}"; do
        test_single_case "$case_name" "${test_cases[$case_name]}" true
    done
    
    # 性能测试
    performance_test
    
    # 检查输出目录
    print_header "检查输出文件"
    local output_dir="./output"
    if [[ -d "$output_dir" ]]; then
        local png_files=($(find "$output_dir" -name "*.png" -type f))
        local png_count=${#png_files[@]}
        
        if [[ $png_count -gt 0 ]]; then
            print_msg "📂 输出目录包含 $png_count 个PNG文件" $GREEN
            
            # 显示最新的几个文件
            if [[ $png_count -le 5 ]]; then
                for file in "${png_files[@]}"; do
                    local size=$(du -h "$file" | cut -f1)
                    print_msg "  - $(basename "$file") ($size)" $CYAN
                done
            else
                print_msg "  最新5个文件:" $CYAN
                ls -lt "$output_dir"/*.png | head -5 | while read -r line; do
                    local filename=$(echo "$line" | awk '{print $9}')
                    local size=$(echo "$line" | awk '{print $5}')
                    print_msg "  - $(basename "$filename") ($(numfmt --to=iec --suffix=B $size))" $CYAN
                done
            fi
        else
            print_msg "⚠️ 输出目录中没有PNG文件" $YELLOW
        fi
    else
        print_msg "⚠️ 输出目录不存在" $YELLOW
    fi
    
    # 测试结果汇总
    print_header "测试结果汇总"
    print_msg "总测试用例: $TOTAL_TESTS" $BLUE
    print_msg "JSON成功: $SUCCESS_COUNT" $GREEN
    print_msg "PNG成功: $PNG_SUCCESS_COUNT" $GREEN
    
    if [[ ${#FAILED_CASES[@]} -gt 0 ]]; then
        print_msg "失败用例: ${#FAILED_CASES[@]}" $RED
        for failed_case in "${FAILED_CASES[@]}"; do
            print_msg "  - $failed_case" $RED
        done
    else
        print_msg "失败用例: 0" $GREEN
    fi
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((SUCCESS_COUNT * 100 / TOTAL_TESTS))
    fi
    
    print_msg "成功率: ${success_rate}%" $CYAN
    
    # 最终结论
    echo
    if [[ $SUCCESS_COUNT -eq $TOTAL_TESTS ]]; then
        print_msg "🎉 所有测试通过！系统运行正常" $GREEN
        print_msg "建议下一步操作:" $CYAN
        echo "  1. 打开 test_page.html 进行可视化测试"
        echo "  2. 检查生成的PNG文件质量"
        echo "  3. 配置真实的飞书应用凭据"
        echo "  4. 准备部署到生产环境"
    else
        print_msg "⚠️ 部分测试失败，请检查配置和依赖" $YELLOW
        print_msg "故障排除建议:" $CYAN
        echo "  1. 检查Flask服务日志"
        echo "  2. 确认所有Python依赖已安装"
        echo "  3. 检查.env配置文件"
        echo "  4. 验证模板文件是否存在"
    fi
    
    # 清理临时文件
    rm -f test_*.png 2>/dev/null || true
}

# 信号处理
trap 'print_msg "\n🛑 测试被中断" $RED; exit 130' INT

# 执行主函数
main "$@"