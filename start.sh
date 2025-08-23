#!/bin/bash
# Feishu Card Bot 启动脚本

# 确保虚拟环境存在
if [ ! -d ".venv" ]; then
    echo "创建虚拟环境..."
    python3 -m venv .venv
fi

# 激活虚拟环境并安装依赖
echo "安装依赖..."
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install python-dotenv

# 确保.env文件存在
if [ ! -f ".env" ]; then
    echo "复制.env配置文件..."
    cp .env.example .env
    echo "请编辑.env文件，填入你的飞书应用ID和密钥"
fi

# 启动应用
echo "启动Flask应用..."
echo "访问 http://localhost:3000"
.venv/bin/python app.py