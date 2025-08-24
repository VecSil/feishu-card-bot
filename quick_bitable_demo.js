/**
 * 飞书多维表格MBTI名片快速演示脚本
 * 用于验证字段配置和基础功能
 * 
 * 使用方法：
 * 1. 在飞书多维表格中打开开发者控制台
 * 2. 复制粘贴此代码并运行
 * 3. 观察输出结果，验证配置是否正确
 */

// 配置项（根据实际情况修改）
const DEMO_CONFIG = {
    // 你的webhook地址
    WEBHOOK_URL: 'https://2584df5b7dea.ngrok-free.app/hook',
    
    // 字段名称映射（必须与你的表格字段名完全一致）
    FIELDS: {
        nickname: '昵称',
        gender: '性别', 
        profession: '职业',
        interests: '兴趣爱好',
        mbti: 'MBTI类型',
        introduction: '一句话介绍',
        wechatQr: '微信二维码',
        // 结果字段
        cardImage: '名片图片',
        imageKey: '图片标识',
        status: '生成状态',
        generatedTime: '生成时间'
    },
    
    // 演示数据
    DEMO_DATA: {
        nickname: '演示用户',
        gender: '保密',
        profession: '产品体验师', 
        interests: '用户研究、交互设计、心理学',
        mbti: 'ENFP',
        introduction: '充满创意的梦想家，热爱探索无限可能',
        wechatQrAttachmentId: '' // 如果有真实的二维码，可以填入file_token
    }
};

/**
 * 主演示函数
 */
async function runQuickDemo() {
    console.log('🎬 开始飞书多维表格MBTI名片快速演示...');
    console.log('配置信息:', DEMO_CONFIG);
    
    try {
        // 第1步：验证基础API可用性
        await testBasicAPIs();
        
        // 第2步：验证表格字段配置
        await testTableFields();
        
        // 第3步：测试单条记录处理
        await testSingleRecord();
        
        // 第4步：演示完整工作流程
        await demonstrateFullWorkflow();
        
        showSuccess('🎉 快速演示完成！所有功能正常');
        
    } catch (error) {
        console.error('❌ 演示过程出错:', error);
        showError(`演示失败: ${error.message}`);
    }
}

/**
 * 测试基础API
 */
async function testBasicAPIs() {
    console.log('\n=== 📋 第1步：基础API测试 ===');
    
    // 测试用户信息
    const user = await bitable.bridge.getUserInfo();
    console.log('✅ 用户信息:', {
        name: user.name,
        open_id: user.open_id ? '已获取' : '未获取'
    });
    
    // 测试表格信息
    const table = await bitable.base.getActiveTable();
    const tableMeta = await table.getMeta();
    console.log('✅ 表格信息:', {
        name: tableMeta.name,
        id: tableMeta.id
    });
    
    // 测试记录选择
    const selection = await bitable.base.getSelection();
    console.log('✅ 当前选择:', {
        recordCount: selection?.recordIds?.length || 0
    });
}

/**
 * 验证表格字段配置
 */
async function testTableFields() {
    console.log('\n=== 🗂️ 第2步：字段配置验证 ===');
    
    const table = await bitable.base.getActiveTable();
    const fieldList = await table.getFieldList();
    
    console.log('📊 表格现有字段:', fieldList.map(f => f.name));
    
    // 检查必需字段
    const requiredFields = Object.values(DEMO_CONFIG.FIELDS);
    const missingFields = [];
    
    for (const fieldName of requiredFields) {
        const field = fieldList.find(f => f.name === fieldName);
        if (field) {
            console.log(`✅ 找到字段: ${fieldName} (类型: ${field.type})`);
        } else {
            console.log(`❌ 缺少字段: ${fieldName}`);
            missingFields.push(fieldName);
        }
    }
    
    if (missingFields.length > 0) {
        console.warn('⚠️ 请添加以下字段到表格中:', missingFields);
        showWarning(`请添加缺少的字段: ${missingFields.join(', ')}`);
    } else {
        console.log('✅ 所有必需字段都已配置');
    }
}

/**
 * 测试单条记录处理
 */
async function testSingleRecord() {
    console.log('\n=== 📝 第3步：记录读取测试 ===');
    
    const table = await bitable.base.getActiveTable();
    const selection = await bitable.base.getSelection();
    
    if (!selection?.recordIds?.length) {
        console.log('ℹ️ 未选择记录，跳过此步骤');
        return;
    }
    
    const recordId = selection.recordIds[0];
    const record = await table.getRecordById(recordId);
    const fields = await record.fields;
    
    console.log('📄 选中记录的字段值:');
    for (const [key, fieldName] of Object.entries(DEMO_CONFIG.FIELDS)) {
        const value = getFieldValue(fields, fieldName);
        console.log(`  ${fieldName}: "${value}"`);
    }
}

/**
 * 演示完整工作流程
 */
async function demonstrateFullWorkflow() {
    console.log('\n=== 🔄 第4步：完整工作流程演示 ===');
    
    const user = await bitable.bridge.getUserInfo();
    
    // 准备演示数据
    const demoData = {
        ...DEMO_CONFIG.DEMO_DATA,
        open_id: user.open_id
    };
    
    console.log('📤 发送演示数据到webhook:', demoData);
    
    try {
        // 模拟webhook调用
        console.log('🔗 正在调用webhook服务...');
        
        const response = await fetch(DEMO_CONFIG.WEBHOOK_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(demoData)
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        const result = await response.json();
        console.log('📥 Webhook响应:', result);
        
        if (result.status === 'ok' && result.image_key) {
            console.log('✅ 名片生成成功!');
            console.log('🎯 关键返回值:');
            console.log(`  image_key: ${result.image_key}`);
            console.log(`  image_url: ${result.image_url}`);
            
            // 演示如何更新表格记录
            await demonstrateRecordUpdate(result);
            
        } else {
            console.error('❌ 名片生成失败:', result.error || '未知错误');
        }
        
    } catch (error) {
        console.error('❌ Webhook调用失败:', error);
        throw error;
    }
}

/**
 * 演示记录更新
 */
async function demonstrateRecordUpdate(result) {
    console.log('\n--- 📝 记录更新演示 ---');
    
    const table = await bitable.base.getActiveTable();
    const selection = await bitable.base.getSelection();
    
    if (!selection?.recordIds?.length) {
        console.log('ℹ️ 未选择记录，创建新记录演示');
        
        // 创建新记录
        const newRecord = await table.addRecord({
            [DEMO_CONFIG.FIELDS.nickname]: DEMO_CONFIG.DEMO_DATA.nickname,
            [DEMO_CONFIG.FIELDS.mbti]: DEMO_CONFIG.DEMO_DATA.mbti,
            [DEMO_CONFIG.FIELDS.cardImage]: result.image_url,
            [DEMO_CONFIG.FIELDS.imageKey]: result.image_key,
            [DEMO_CONFIG.FIELDS.status]: '✅ 演示完成',
            [DEMO_CONFIG.FIELDS.generatedTime]: new Date().toLocaleString('zh-CN')
        });
        
        console.log('✅ 新记录创建成功:', newRecord.id);
        
    } else {
        // 更新选中的记录
        const recordId = selection.recordIds[0];
        
        await table.setRecord(recordId, {
            [DEMO_CONFIG.FIELDS.cardImage]: result.image_url,
            [DEMO_CONFIG.FIELDS.imageKey]: result.image_key,
            [DEMO_CONFIG.FIELDS.status]: '✅ 演示完成',
            [DEMO_CONFIG.FIELDS.generatedTime]: new Date().toLocaleString('zh-CN')
        });
        
        console.log('✅ 记录更新成功:', recordId);
    }
}

/**
 * 获取字段值的辅助函数
 */
function getFieldValue(fields, fieldName) {
    if (!fields[fieldName]) return '';
    
    const field = fields[fieldName];
    
    if (Array.isArray(field)) {
        return field.length > 0 ? (field[0].text || field[0].name || field[0]) : '';
    } else if (typeof field === 'object') {
        return field.text || field.name || field.toString();
    } else {
        return field.toString();
    }
}

/**
 * UI提示函数
 */
function showSuccess(message) {
    console.log(`✅ ${message}`);
    if (typeof bitable !== 'undefined' && bitable.ui) {
        bitable.ui.showToast({
            toastType: 'success',
            message: message
        });
    }
}

function showError(message) {
    console.error(`❌ ${message}`);
    if (typeof bitable !== 'undefined' && bitable.ui) {
        bitable.ui.showToast({
            toastType: 'error',
            message: message
        });
    }
}

function showWarning(message) {
    console.warn(`⚠️ ${message}`);
    if (typeof bitable !== 'undefined' && bitable.ui) {
        bitable.ui.showToast({
            toastType: 'warning',
            message: message
        });
    }
}

/**
 * 配置检查函数
 */
function checkConfiguration() {
    console.log('\n🔧 配置检查:');
    
    const issues = [];
    
    if (!DEMO_CONFIG.WEBHOOK_URL || DEMO_CONFIG.WEBHOOK_URL.includes('your-domain')) {
        issues.push('请更新WEBHOOK_URL为你的实际地址');
    }
    
    if (issues.length > 0) {
        console.warn('⚠️ 配置问题:');
        issues.forEach(issue => console.warn(`  - ${issue}`));
        return false;
    }
    
    console.log('✅ 配置检查通过');
    return true;
}

// 自动运行配置检查
if (checkConfiguration()) {
    console.log('\n🚀 准备就绪，运行 runQuickDemo() 开始演示');
} else {
    console.log('\n❌ 请先修复配置问题');
}

// 导出函数供手动调用
if (typeof window !== 'undefined') {
    window.MBTIDemo = {
        runQuickDemo,
        checkConfiguration,
        DEMO_CONFIG
    };
}

// 提供简化的启动函数
function startDemo() {
    if (checkConfiguration()) {
        runQuickDemo();
    }
}

console.log('\n📖 使用指南:');
console.log('1. 修改 DEMO_CONFIG 中的 WEBHOOK_URL');
console.log('2. 确认字段名称与你的表格一致'); 
console.log('3. 运行 startDemo() 开始演示');
console.log('4. 或运行 runQuickDemo() 跳过配置检查');