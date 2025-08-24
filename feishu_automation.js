/**
 * 飞书多维表格 MBTI名片自动生成脚本
 * 功能：调用webhook生成名片，并将结果更新到多维表格
 * 使用方式：在飞书多维表格的自动化流程中运行此脚本
 */

// 配置项
const CONFIG = {
    // 你的webhook地址（ngrok或云服务器地址）
    WEBHOOK_URL: 'https://2584df5b7dea.ngrok-free.app/hook',
    
    // 字段映射配置（根据你的表格字段名调整）
    FIELD_MAPPING: {
        nickname: '昵称',
        gender: '性别', 
        profession: '职业',
        interests: '兴趣爱好',
        mbti: 'MBTI类型',
        introduction: '一句话介绍',
        wechatQrAttachmentId: '微信二维码',
        // 结果字段
        cardImage: '名片图片',
        imageKey: '图片标识', 
        status: '生成状态',
        generatedTime: '生成时间',
        localBackup: '本地备份'
    },
    
    // 状态选项
    STATUS: {
        PENDING: '待生成',
        PROCESSING: '生成中',
        COMPLETED: '✅ 已完成', 
        FAILED: '❌ 失败'
    }
};

/**
 * 主函数：批量生成MBTI名片
 */
async function generateMBTICards() {
    try {
        console.log('🚀 开始MBTI名片批量生成流程...');
        
        // 获取当前用户信息
        const user = await bitable.bridge.getUserInfo();
        if (!user?.open_id) {
            throw new Error('无法获取用户信息，请确保已登录飞书');
        }
        
        // 获取当前表格和选中记录
        const table = await bitable.base.getActiveTable();
        const selection = await bitable.base.getSelection();
        
        if (!selection?.recordIds?.length) {
            bitable.ui.showToast({
                toastType: 'warning',
                message: '请先选择要生成名片的记录'
            });
            return;
        }
        
        console.log(`📝 共选择了 ${selection.recordIds.length} 条记录`);
        
        // 批量处理选中记录
        let successCount = 0;
        let failCount = 0;
        
        for (let i = 0; i < selection.recordIds.length; i++) {
            const recordId = selection.recordIds[i];
            console.log(`\n🔄 处理第 ${i + 1}/${selection.recordIds.length} 条记录: ${recordId}`);
            
            try {
                // 处理单条记录
                const success = await processRecord(table, recordId, user.open_id);
                if (success) {
                    successCount++;
                } else {
                    failCount++;
                }
                
                // 添加延迟避免API频率限制
                if (i < selection.recordIds.length - 1) {
                    await sleep(1500); // 1.5秒延迟
                }
                
            } catch (error) {
                console.error(`❌ 处理记录 ${recordId} 失败:`, error);
                failCount++;
                
                // 更新失败状态
                await updateRecordStatus(table, recordId, CONFIG.STATUS.FAILED, {
                    errorMessage: error.message
                });
            }
        }
        
        // 显示完成总结
        const message = `🎉 名片生成完成！\n✅ 成功: ${successCount} 张\n❌ 失败: ${failCount} 张`;
        console.log(message);
        
        bitable.ui.showToast({
            toastType: successCount > 0 ? 'success' : 'error',
            message: message
        });
        
    } catch (error) {
        console.error('❌ 批量生成流程失败:', error);
        bitable.ui.showToast({
            toastType: 'error',
            message: `生成失败: ${error.message}`
        });
    }
}

/**
 * 处理单条记录
 */
async function processRecord(table, recordId, userOpenId) {
    try {
        // 1. 获取记录数据
        const record = await table.getRecordById(recordId);
        const fields = await record.fields;
        
        const nickname = getFieldValue(fields, CONFIG.FIELD_MAPPING.nickname);
        console.log(`👤 正在为 "${nickname}" 生成名片...`);
        
        // 2. 更新为生成中状态
        await updateRecordStatus(table, recordId, CONFIG.STATUS.PROCESSING);
        
        // 3. 构建webhook请求数据
        const webhookData = {
            nickname: nickname,
            gender: getFieldValue(fields, CONFIG.FIELD_MAPPING.gender),
            profession: getFieldValue(fields, CONFIG.FIELD_MAPPING.profession), 
            interests: getFieldValue(fields, CONFIG.FIELD_MAPPING.interests),
            mbti: getFieldValue(fields, CONFIG.FIELD_MAPPING.mbti),
            introduction: getFieldValue(fields, CONFIG.FIELD_MAPPING.introduction),
            wechatQrAttachmentId: getAttachmentToken(fields, CONFIG.FIELD_MAPPING.wechatQrAttachmentId),
            open_id: userOpenId
        };
        
        console.log('📤 发送webhook请求...', {
            nickname: webhookData.nickname,
            mbti: webhookData.mbti,
            hasQr: !!webhookData.wechatQrAttachmentId
        });
        
        // 4. 调用webhook生成名片
        const response = await fetch(CONFIG.WEBHOOK_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(webhookData)
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        const result = await response.json();
        console.log('📥 webhook响应:', result);
        
        // 5. 处理生成结果
        if (result.status === 'ok' && result.image_key) {
            // 成功：更新记录信息
            await table.setRecord(recordId, {
                [CONFIG.FIELD_MAPPING.cardImage]: result.image_url,
                [CONFIG.FIELD_MAPPING.imageKey]: result.image_key,
                [CONFIG.FIELD_MAPPING.status]: CONFIG.STATUS.COMPLETED,
                [CONFIG.FIELD_MAPPING.generatedTime]: new Date().toLocaleString('zh-CN'),
                [CONFIG.FIELD_MAPPING.localBackup]: result.local_image_url
            });
            
            console.log(`✅ ${nickname} 的名片生成成功`);
            return true;
            
        } else {
            throw new Error(result.error || '服务返回未知错误');
        }
        
    } catch (error) {
        console.error(`❌ 处理记录失败:`, error);
        
        // 更新失败状态  
        await updateRecordStatus(table, recordId, CONFIG.STATUS.FAILED, {
            errorMessage: error.message
        });
        
        return false;
    }
}

/**
 * 更新记录状态
 */
async function updateRecordStatus(table, recordId, status, extra = {}) {
    try {
        const updateData = {
            [CONFIG.FIELD_MAPPING.status]: status
        };
        
        if (status === CONFIG.STATUS.PROCESSING) {
            updateData[CONFIG.FIELD_MAPPING.generatedTime] = '生成中...';
        }
        
        if (extra.errorMessage) {
            // 如果表格有错误信息字段，可以添加
            console.log('错误信息:', extra.errorMessage);
        }
        
        await table.setRecord(recordId, updateData);
        
    } catch (error) {
        console.error('更新记录状态失败:', error);
    }
}

/**
 * 获取字段值（兼容不同字段类型）
 */
function getFieldValue(fields, fieldName) {
    if (!fields[fieldName]) return '';
    
    const field = fields[fieldName];
    
    // 处理不同类型的字段
    if (Array.isArray(field)) {
        return field.length > 0 ? (field[0].text || field[0]) : '';
    } else if (typeof field === 'object') {
        return field.text || field.toString();
    } else {
        return field.toString();
    }
}

/**
 * 获取附件字段的file_token
 */
function getAttachmentToken(fields, fieldName) {
    if (!fields[fieldName]) return '';
    
    const attachments = fields[fieldName];
    if (Array.isArray(attachments) && attachments.length > 0) {
        return attachments[0].file_token || attachments[0].token || '';
    }
    
    return '';
}

/**
 * 延迟函数
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * 快速测试单条记录
 */
async function testSingleRecord() {
    try {
        const table = await bitable.base.getActiveTable();
        const selection = await bitable.base.getSelection();
        const user = await bitable.bridge.getUserInfo();
        
        if (!selection?.recordIds?.length) {
            bitable.ui.showToast({
                toastType: 'warning', 
                message: '请选择一条记录进行测试'
            });
            return;
        }
        
        const recordId = selection.recordIds[0];
        console.log('🧪 测试单条记录:', recordId);
        
        const success = await processRecord(table, recordId, user.open_id);
        
        bitable.ui.showToast({
            toastType: success ? 'success' : 'error',
            message: success ? '✅ 测试成功' : '❌ 测试失败'
        });
        
    } catch (error) {
        console.error('测试失败:', error);
        bitable.ui.showToast({
            toastType: 'error',
            message: `测试失败: ${error.message}`
        });
    }
}

// 导出主要函数（供自动化流程调用）
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        generateMBTICards,
        testSingleRecord,
        CONFIG
    };
} else {
    // 浏览器环境，挂载到全局
    window.MBTICardGenerator = {
        generateMBTICards,
        testSingleRecord,
        CONFIG
    };
}

// 自动执行（可选，根据触发方式调整）
// generateMBTICards();