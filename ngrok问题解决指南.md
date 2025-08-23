# 🚨 ngrok隧道问题解决指南

## 问题现象

用户收到错误信息：
```json
{
  "$startTime": 1755935075394,
  "$endTime": 1755935076025,
  "body": "The endpoint 128598868da9.ngrok-free.app is offline.\r\n\r\nERR_NGROK_3200\r\n",
  "status_code": 404
}
```

## 🔍 问题分析

### 根本原因
- **ERR_NGROK_3200**: ngrok隧道离线/不可用
- **域名过期**: `128598868da9.ngrok-free.app` 已失效
- **URL变更**: ngrok免费版重启后会生成新的随机域名

### 影响范围
- ❌ 飞书webhook无法到达您的服务器
- ❌ 用户无法收到生成的名片
- ✅ 服务器本身运行正常
- ✅ 名片生成功能正常

## ⚡ 立即解决方案

### 步骤1: 检查并修复URL
```bash
# 运行自动修复脚本
./fix_ngrok_url.sh
```

### 步骤2: 更新飞书配置
根据修复脚本的输出，更新飞书多维表格中的webhook地址：

1. **打开飞书多维表格** → **自动化**
2. **编辑现有的HTTP请求自动化**
3. **修改URL地址**:
   ```
   旧地址: https://128598868da9.ngrok-free.app/hook
   新地址: https://ce94f14ec33c.ngrok-free.app/hook  ← 使用修复脚本提供的新地址
   ```
4. **保存并测试**

### 步骤3: 验证修复效果
```bash
# 测试webhook功能
curl -X POST "https://ce94f14ec33c.ngrok-free.app/hook" \
  -H "Content-Type: application/json" \
  -d '{"name": "测试用户", "title": "工程师"}'
```

## 🔄 长期解决方案

### 方案1: 自动监控系统 (推荐)
```bash
# 启动自动监控(后台运行)
nohup ./monitor_and_fix.sh > monitor.log 2>&1 &

# 查看监控日志
tail -f monitor.log
```

**特性**:
- ✅ 每30秒检查一次URL状态
- ✅ URL变更时自动通知
- ✅ 服务异常时自动重试
- ✅ 详细的状态日志记录

### 方案2: 升级ngrok付费版
```bash
# 优势
- 固定域名 (不再变更)
- 更高的稳定性
- 更多并发连接
- 技术支持

# 价格: $8/月起
```

### 方案3: 使用其他隧道工具
```bash
# 选项1: localtunnel (备用)
lt --port 3000

# 选项2: serveo
ssh -R 80:localhost:3000 serveo.net

# 选项3: frp自建
./frpc -c frpc.ini
```

## 📋 预防措施

### 启动时检查清单
```bash
# 1. 检查ngrok状态
curl -s http://localhost:4040/api/tunnels | grep public_url

# 2. 验证服务健康
curl https://your-current-ngrok-url/healthz

# 3. 测试完整流程
curl -X POST https://your-current-ngrok-url/hook -d '...'
```

### 自动化启动脚本
```bash
#!/bin/bash
# start_full_system.sh

echo "🚀 启动完整系统..."

# 1. 启动Flask应用
python3 app.py &
FLASK_PID=$!

# 2. 启动ngrok
ngrok http 3000 &
NGROK_PID=$!

# 3. 等待服务就绪
sleep 5

# 4. 获取并显示URL
./fix_ngrok_url.sh

# 5. 启动监控
nohup ./monitor_and_fix.sh > monitor.log 2>&1 &

echo "✅ 系统启动完成"
echo "📊 监控日志: tail -f monitor.log"
```

## 🔧 故障排除

### 问题1: ngrok无法启动
```bash
# 检查端口占用
lsof -i :4040

# 重启ngrok
pkill ngrok
ngrok http 3000
```

### 问题2: Flask应用无响应
```bash
# 检查进程
ps aux | grep python

# 重启应用
pkill -f "python.*app.py"
python3 app.py
```

### 问题3: URL仍然无法访问
```bash
# 检查防火墙
# 检查网络连接
ping ngrok.com

# 尝试不同区域
ngrok http --region=us 3000
ngrok http --region=eu 3000
```

## 📊 监控和告警

### 日志监控
```bash
# 实时监控ngrok状态
watch -n 5 'curl -s http://localhost:4040/api/tunnels | jq .'

# 监控Flask应用日志
tail -f flask.log

# 监控系统资源
htop
```

### 告警设置
```bash
# 环境变量配置
export NOTIFICATION_WEBHOOK="https://your-slack-webhook"

# 告警脚本会在URL变更时自动发送通知
```

## 💡 最佳实践

### 开发环境
- 使用监控脚本确保服务稳定
- 定期检查ngrok状态
- 保存当前有效URL备用

### 生产环境
- 强烈建议升级到ngrok付费版
- 配置固定域名和SSL证书
- 部署到云服务器避免依赖本地ngrok

### 应急预案
```bash
# 预案1: 快速切换到localtunnel
pkill ngrok
lt --port 3000

# 预案2: 使用备用服务器
scp *.py backup-server:~/
ssh backup-server 'python3 app.py'
```

## 📈 性能优化

### ngrok优化
```bash
# 选择最近的区域
ngrok http --region=ap 3000  # 亚太地区

# 启用压缩
ngrok http --compression 3000

# 增加连接超时
ngrok http --timeout=60s 3000
```

### 系统优化
- 增加Flask应用的worker数量
- 配置nginx反向代理
- 启用缓存机制

## 🎯 总结

### 问题解决步骤
1. ✅ **立即修复**: 运行 `./fix_ngrok_url.sh`
2. ✅ **更新配置**: 在飞书中更新webhook URL  
3. ✅ **验证功能**: 测试完整的名片生成流程
4. ✅ **启动监控**: 运行 `./monitor_and_fix.sh`

### 核心要点
- **问题根源**: ngrok免费版URL会变更
- **解决方案**: 自动检测和配置更新
- **预防措施**: 实时监控和告警系统
- **长期建议**: 升级到付费版或部署到云服务器

---

**🎉 恢复正常**: 按照本指南操作后，您的飞书名片生成系统将恢复正常工作，并具备自动故障检测和修复能力！