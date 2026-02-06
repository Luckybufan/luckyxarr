-- 载入插件

local currentPath = debug.getinfo(1, "S").source:sub(2)
local projectDir = currentPath:match("(.*/)")
package.path = package.path .. ";." .. projectDir .. "../../common/?.lua"

local http = require("http")
local json = require("json")
local helper = require("helper")

local orderHelper = require("orderHelper")

-- 生成随机字符串
local function random_string(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""
    for i = 1, length do
        local index = math.random(1, #chars)
        result = result .. string.sub(chars, index, index)
    end
    return result
end

--- 插件信息
plugin = {
    info = {
        name = 'lucky_fuyou1',
        title = '富友支付(前置商户)',
        author = '凡世',
        description = "富友支付通用SDK",
        link = 'https://www.fuiou.com/',
        version = "1.0.0",
        -- 支持支付类型
        channels = {
            alipay = {
                {
                    label = '富友支付(前置商户)',
                    value = 'alipay_lucky_fuyou1'
                },
            },
            wxpay = {
                {
                    label = '富友支付(前置商户)',
                    value = 'wxpay_lucky_fuyou1'
                },
            },
            bank = {
                {
                    label = '富友支付(前置商户)',
                    value = 'bank_lucky_fuyou1'
                },
            },
        },
        options = {
            callback = 1,
            detection_interval = 0,
            -- 定时任务
            crontab_list = {{
                                crontab = "*/6 * * * * *",
                                fun = "check_order",
                                args = "",
                                name = "富友支付检查订单支付状态", -- 本插件内唯一
                                scope = "order" -- 目标范围 order 订单(只查询订单未支付状态) account 账号 (只查询账号在线状态) system 全局
                            }},
            -- 配置项
            options = {{
                title = "请输入商户提示信息（红色显示）", 
                key = "merchant_tip", 
                default = "请确保商户号和密钥配置正确，否则支付将失败！"
            }}
        },

    }
}

function plugin.pluginInfo()
    return json.encode(plugin.info)
end

-- 获取form表单
function plugin.formItems(payType, payChannel)
    return json.encode({
        inputs = {
            {
                name = 'appid',
                label = '商户号',
                type = 'input',
                default = "",
                placeholder = "请输入商户号",
                options = {
                    tip = '<span style="color: red;">请确保商户号配置正确，否则支付将失败！</span>',
                },
                rules = {
                    {
                        required = true,
                        trigger = { "input", "blur" },
                        message = "请输入"
                    }
                }
            },
            {
                name = 'appkey',
                label = '商户密钥',
                type = 'password',
                default = "",
                placeholder = "请输入商户密钥",
                options = {
                    tip = '<span style="color: red;">请确保密钥配置正确，否则支付将失败！</span>',
                },
                rules = {
                    {
                        required = true,
                        trigger = { "input", "blur" },
                        message = "请输入"
                    }
                }
            },
            {
                name = 'appurl',
                label = '订单号前缀',
                type = 'input',
                default = "",
                placeholder = "请输入订单号前缀",
                options = {
                    tip = '<span style="color: red;">请确保订单号前缀配置正确，否则支付将失败！</span>',
                },
                rules = {
                    {
                        required = true,
                        trigger = { "input", "blur" },
                        message = "请输入"
                    }
                }
            },
            {
                name = 'contact',
                label = '',
                type = 'html',
                default = '',
                placeholder = '',
                options = {
                    html = '<div style="color: blue; margin-top: 15px; padding: 10px; border: 1px solid blue; border-radius: 4px;">富友开户联系QQ：2905099491</div>',
                }
            },
        }
    })
end

-- 通用下单
function plugin._addOrder(pay_type, orderInfo, pluginOptions)
    local appid = pluginOptions['appid']
    local appkey = pluginOptions['appkey']
    local appurl = pluginOptions['appurl']
    local order_amt = orderInfo['trade_amount']
    local out_trade_no = appurl .. orderInfo['order_id']
    local notify_url = orderInfo['notify_url']
    local clientip = orderInfo['client_ip']
    local subject = orderInfo['subject']
    
    -- 组装请求参数
    local req = {
        version = "1.0",
        mchnt_cd = appid,
        random_str = random_string(32),
        order_type = pay_type,
        order_amt = tostring(order_amt),
        mchnt_order_no = out_trade_no,
        txn_begin_ts = os.date("%Y%m%d%H%M%S"),
        goods_des = subject,
        term_id = tostring(math.random(10000000, 99999999)),
        term_ip = clientip,
        notify_url = notify_url,
    }
    
    -- 生成签名
    local param_ord = {'mchnt_cd', 'order_type', 'order_amt', 'mchnt_order_no', 'txn_begin_ts', 'goods_des', 'term_id', 'term_ip', 'notify_url', 'random_str', 'version'}
    local signStr = ''
    for _, key in ipairs(param_ord) do
        signStr = signStr .. req[key] .. '|'
    end
    signStr = signStr .. appkey
    local sign = helper.md5(signStr)
    req['sign'] = sign
    
    -- 发送请求
    local apiurl = "https://aipay-cloud.fuioupay.com/aggregatePay/preCreate"
    local headers = {
        ["content-type"] = "application/json"
    }
    
    local response = http.post(apiurl, {
        headers = headers,
        body = json.encode(req)
    })
    
    if not response or not response.body then
        error('请求失败: ' .. (response and response.error or '未知错误'))
    end
    
    local returnInfo = json.decode(response.body)
    if not returnInfo then
        error('返回数据解析失败')
    end
    
    if returnInfo['result_code'] ~= "000000" then
        error(returnInfo['result_msg'] or '下单失败')
    end
    
    local code_url = returnInfo['qr_code']
    if not code_url then
        error('返回数据缺少二维码链接')
    end
    
    return code_url, returnInfo['transaction_id'] or ""
end

function plugin.create(pOrderInfo, pluginOptions, pAccountInfo, pDeviceInfo)
    local orderInfo = type(pOrderInfo) == 'string' and json.decode(pOrderInfo) or pOrderInfo
    local options = type(pluginOptions) == 'string' and json.decode(pluginOptions) or pluginOptions
    
    local pay_type = orderInfo['pay_type']
    
    local code_url, transaction_id
    local status, err = pcall(function()
        if pay_type == "alipay" then
            code_url, transaction_id = plugin._addOrder('ALIPAY', orderInfo, options)
        elseif pay_type == "wxpay" then
            code_url, transaction_id = plugin._addOrder('WECHAT', orderInfo, options)
        elseif pay_type == "bank" then
            code_url, transaction_id = plugin._addOrder('UNIONPAY', orderInfo, options)
        else
            error('不支持的支付类型')
        end
    end)
    
    if not status then
        return json.encode({
            type = 'error',
            err_code = 500,
            err_message = '下单失败！' .. err
        })
    end
    
    return json.encode({
        type = "qrcode",
        qrcode = code_url,
        url = code_url,
        content = "",
        out_trade_no = transaction_id,
        err_code = 200,
        err_message = ""
    })
end

-- 支付回调
function plugin.notify(pRequest, pOrderInfo, pParams, pluginOptions)
    local request = json.decode(pRequest)
    local orderInfo = json.decode(pOrderInfo)
    local options = json.decode(pluginOptions)

    -- 获取请求数据
    local reqData = request['method'] == 'POST' and request['body'] or request['query']

    -- 检查必要字段
    if not reqData or type(reqData) ~= 'table' then
        return json.encode({
            error_code = 500,
            error_message = "请求数据异常",
            response = ""
        })
    end

    -- 验证签名
    local sign = reqData['sign']
    if not sign then
        return json.encode({
            error_code = 500,
            error_message = "签名缺失",
            response = ""
        })
    end

    -- 生成签名
    local appkey = options['appkey']
    if not appkey then
        return json.encode({
            error_code = 500,
            error_message = "商户密钥未配置",
            response = ""
        })
    end

    local param_ord = {'mchnt_cd', 'mchnt_order_no', 'settle_order_amt', 'order_amt', 'txn_fin_ts', 'reserved_fy_settle_dt', 'random_str'}
    local signStr = ''
    for _, key in ipairs(param_ord) do
        signStr = signStr .. reqData[key] .. '|'
    end
    signStr = signStr .. appkey
    local genSign = helper.md5(signStr)

    if genSign ~= sign then
        return json.encode({
            error_code = 500,
            error_message = "签名校验失败",
            response = ""
        })
    end

    -- 验证商户号
    if reqData['mchnt_cd'] ~= options['appid'] then
        return json.encode({
            error_code = 500,
            error_message = "交易商户号异常",
            response = ""
        })
    end

    -- 检查支付状态
    if reqData['result_code'] ~= "000000" or reqData['result_msg'] ~= "SUCCESS" then
        return json.encode({
            error_code = 500,
            error_message = "交易未完成",
            response = ""
        })
    end

    -- 提取订单号，优先使用orderInfo中的order_id
    local trade_no = orderInfo and orderInfo.order_id or ""

    -- 通知订单处理完成
    local err_code, err_message, response = orderHelper.notify_process(json.encode({
        out_trade_no = reqData['transaction_id'] or "",
        trade_no = trade_no,
        amount = tonumber(reqData['order_amt'] or 0),
    }), pParams, pluginOptions)

    return json.encode({
        error_code = err_code,
        error_message = err_message,
        response = response,
    })
end

-- 订单查询
function plugin._query_order(orderInfo, pluginOptions)
    local appid = pluginOptions['appid']
    local appkey = pluginOptions['appkey']
    local appurl = pluginOptions['appurl']
    local order_amt = orderInfo['trade_amount']
    local out_trade_no = appurl .. orderInfo['order_id']
    local pay_type = orderInfo['pay_type']
    
    -- 订单类型映射
    local order_type = ""
    if pay_type == "alipay" then
        order_type = "ALIPAY"
    elseif pay_type == "wxpay" then
        order_type = "WECHAT"
    elseif pay_type == "bank" then
        order_type = "UNIONPAY"
    else
        return nil, "不支持的支付类型"
    end
    
    -- 组装请求参数
    local req = {
        version = "1.0",
        mchnt_cd = appid,
        random_str = random_string(32),
        order_type = order_type,
        mchnt_order_no = out_trade_no,
        term_id = random_string(8)
    }
    
    -- 生成签名
    local signStr = req.mchnt_cd .. '|' .. req.order_type .. '|' .. req.mchnt_order_no .. '|' .. req.term_id .. '|' .. req.random_str .. '|' .. req.version .. '|' .. appkey
    local sign = helper.md5(signStr)
    req['sign'] = sign
    
    -- 发送请求
    local apiurl = "https://aipay-cloud.fuioupay.com/aggregatePay/commonQuery"
    local headers = {
        ["content-type"] = "application/json"
    }
    
    local response = http.post(apiurl, {
        headers = headers,
        body = json.encode(req)
    })
    
    if not response or not response.body then
        return nil, '请求失败: ' .. (response and response.error or '未知错误')
    end
    
    local returnInfo = json.decode(response.body)
    if not returnInfo then
        return nil, '返回数据解析失败'
    end
    
    if returnInfo['result_code'] ~= "000000" then
        return nil, returnInfo['result_msg'] or '查询失败'
    end
    
    return returnInfo
end

-- 检查订单
function plugin.check_order(pOrderInfo, pAccountInfo, pPluginOption, crontabExtArgs)
    local orderInfo = json.decode(pOrderInfo)
    local accountInfo = json.decode(pAccountInfo)
    local pluginOption = json.decode(pPluginOption)
    
    -- 获取插件配置
    local accountOptions = {}
    if accountInfo.options then
        accountOptions = json.decode(accountInfo.options)
    end
    
    if not accountOptions.appid or accountOptions.appid == "" then
        return json.encode({
            err_code = 500,
            err_message = "商户号异常"
        })
    end
    
    -- 查询订单状态
    local result, err = plugin._query_order(orderInfo, accountOptions)
    if not result then
        return json.encode({
            err_code = 500,
            err_message = "订单查询失败: " .. err
        })
    end
    
    -- 检查订单状态
    local trans_stat = result['trans_stat']
    if trans_stat == "SUCCESS" then
        -- 订单支付成功，通知订单处理完成
        local trade_no = orderInfo and orderInfo.order_id or ""
        
        orderHelper.notify_process(json.encode({
            out_trade_no = result['transaction_id'] or "",
            trade_no = trade_no,
            amount = tonumber(result['order_amt'] or 0),
        }), pPluginOption, json.encode(accountOptions))
        
        return json.encode({
            err_code = 200,
            err_message = "订单支付成功"
        })
    elseif trans_stat == "NOTPAY" or trans_stat == "USERPAYING" then
        -- 订单未支付或用户支付中
        return json.encode({
            err_code = 502,
            err_message = "订单未支付，等待回调通知"
        })
    else
        -- 其他状态
        return json.encode({
            err_code = 500,
            err_message = "订单状态异常: " .. trans_stat
        })
    end
end

-- 同步回调
function plugin._return(request, orderInfo, params, pluginOptions)
    return json.encode({
        error_code = 0,
        error_message = "success",
        action = "render",
        data = {
            type = "page",
            page = "return"
        }
    })
end

-- 支付数据渲染
function plugin.render(pOrderInfo, pOldPayData, pAccountInfo, pDeviceInfo)
    local oldPayData = json.decode(pOldPayData)
    local deviceInfo = json.decode(pDeviceInfo)
    
    if deviceInfo and deviceInfo.is_mobile then
        return json.encode({
            error_code = 200,
            error_message = "success",
            action = "render",
            data = {
                type = "jump",
                url = oldPayData.qrcode
            }
        })
    end
    
    return json.encode({
        error_code = 200,
        error_message = "success",
        action = "",
        data = oldPayData
    })
end