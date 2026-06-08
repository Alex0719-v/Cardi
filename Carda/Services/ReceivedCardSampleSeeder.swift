//
//  ReceivedCardSampleSeeder.swift
//  Carda
//

import Foundation
import SwiftData

private struct SampleReceivedCard {
    let name: String
    let phone: String
    let organization: String
    let position: String
    let email: String
    let address: String

    var key: String {
        "\(name)|\(phone)"
    }
}

@MainActor
enum ReceivedCardSampleSeeder {
    static func seedIfNeeded(in modelContext: ModelContext, existingCards: [BusinessCard]) {
        let existingSampleKeys = Set(
            existingCards
                .filter { $0.ownerKind == .received }
                .compactMap(sampleKey)
        )
        let missingSamples = samples.filter { !existingSampleKeys.contains($0.key) }
        guard !missingSamples.isEmpty else { return }

        let now = Date()
        for (index, sample) in missingSamples.enumerated() {
            let fields = [
                CardInfoField(kind: .phone, value: sample.phone, sortOrder: 0),
                CardInfoField(kind: .email, value: sample.email, sortOrder: 1),
                CardInfoField(kind: .address, value: sample.address, sortOrder: 2)
            ]
            let date = now.addingTimeInterval(TimeInterval(-index * 600))
            let card = BusinessCard(
                ownerKind: .received,
                name: sample.name,
                phoneticName: "",
                position: sample.position,
                organizationName: sample.organization,
                fields: fields,
                createdAt: date,
                updatedAt: date,
                receivedAt: date
            )
            modelContext.insert(card)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    private static func sampleKey(for card: BusinessCard) -> String? {
        guard let phone = card.sortedFields.first(where: { $0.kind == .phone })?.value else { return nil }
        return "\(card.name)|\(phone)"
    }

    private static let samples: [SampleReceivedCard] = [
        SampleReceivedCard(name: "安晨", phone: "13800010001", organization: "星辰科技有限公司", position: "产品经理", email: "anchen@demo.com", address: "上海市浦东新区张江高科技园区88号"),
        SampleReceivedCard(name: "安悦", phone: "13800010002", organization: "智联未来科技有限公司", position: "市场总监", email: "anyue@demo.com", address: "北京市朝阳区望京SOHO T2座"),
        SampleReceivedCard(name: "白露", phone: "13800010003", organization: "云海数字科技有限公司", position: "UI设计师", email: "bailu@demo.com", address: "杭州市西湖区文三路168号"),
        SampleReceivedCard(name: "包宇航", phone: "13800010004", organization: "天际创新科技有限公司", position: "软件工程师", email: "baoyh@demo.com", address: "深圳市南山区科技园南路66号"),
        SampleReceivedCard(name: "陈晨", phone: "13800010005", organization: "华创信息技术有限公司", position: "项目经理", email: "chenchen@demo.com", address: "广州市天河区珠江新城88号"),
        SampleReceivedCard(name: "陈雨菲", phone: "13800010006", organization: "极光传媒有限公司", position: "品牌策划", email: "chenyf@demo.com", address: "成都市高新区天府大道588号"),
        SampleReceivedCard(name: "邓嘉豪", phone: "13800010007", organization: "远见咨询有限公司", position: "商务经理", email: "dengjh@demo.com", address: "南京市建邺区江东中路99号"),
        SampleReceivedCard(name: "丁一凡", phone: "13800010008", organization: "鼎盛能源集团", position: "运营主管", email: "dingyf@demo.com", address: "苏州市工业园区金鸡湖大道8号"),
        SampleReceivedCard(name: "鄂子轩", phone: "13800010009", organization: "智慧医疗科技有限公司", position: "产品专员", email: "ezx@demo.com", address: "武汉市东湖高新区光谷软件园"),
        SampleReceivedCard(name: "方可欣", phone: "13800010010", organization: "蓝图设计事务所", position: "室内设计师", email: "fangkx@demo.com", address: "重庆市渝中区解放碑商业街"),
        SampleReceivedCard(name: "高宇辰", phone: "13800010011", organization: "星图人工智能有限公司", position: "算法工程师", email: "gaoyc@demo.com", address: "北京市海淀区中关村大街1号"),
        SampleReceivedCard(name: "郭佳怡", phone: "13800010012", organization: "创维电商有限公司", position: "电商运营经理", email: "guojy@demo.com", address: "杭州市余杭区梦想小镇"),
        SampleReceivedCard(name: "韩思远", phone: "13800010013", organization: "华兴金融服务有限公司", position: "投资顾问", email: "hansy@demo.com", address: "上海市黄浦区人民广场金融中心"),
        SampleReceivedCard(name: "何雨桐", phone: "13800010014", organization: "瑞丰地产集团", position: "市场经理", email: "heyt@demo.com", address: "天津市和平区南京路188号"),
        SampleReceivedCard(name: "黄子墨", phone: "13800010015", organization: "新航物流有限公司", position: "供应链主管", email: "huangzm@demo.com", address: "宁波市鄞州区国际物流园"),
        SampleReceivedCard(name: "江知夏", phone: "13800010016", organization: "未来教育科技有限公司", position: "产品运营", email: "jiangzx@demo.com", address: "长沙市岳麓区麓谷科技园"),
        SampleReceivedCard(name: "蒋文博", phone: "13800010017", organization: "智创机器人有限公司", position: "机械工程师", email: "jiangwb@demo.com", address: "苏州市高新区科技城"),
        SampleReceivedCard(name: "康乐", phone: "13800010018", organization: "康达医疗器械有限公司", position: "销售总监", email: "kangle@demo.com", address: "济南市历下区经十路999号"),
        SampleReceivedCard(name: "李安然", phone: "13800010019", organization: "云帆科技有限公司", position: "CEO", email: "liaran@demo.com", address: "深圳市福田区深南大道600号"),
        SampleReceivedCard(name: "林沐阳", phone: "13800010020", organization: "蓝海软件有限公司", position: "技术总监", email: "linmy@demo.com", address: "厦门市思明区软件园二期"),
        SampleReceivedCard(name: "马若曦", phone: "13800010021", organization: "盛世文化传媒有限公司", position: "创意总监", email: "marx@demo.com", address: "西安市雁塔区曲江新区"),
        SampleReceivedCard(name: "莫子涵", phone: "13800010022", organization: "新视界广告有限公司", position: "客户经理", email: "mozh@demo.com", address: "郑州市郑东新区商务内环路"),
        SampleReceivedCard(name: "宁嘉怡", phone: "13800010023", organization: "光启智能科技有限公司", position: "数据分析师", email: "ningjy@demo.com", address: "合肥市高新区创新大道"),
        SampleReceivedCard(name: "欧阳晨曦", phone: "13800010024", organization: "远航国际贸易有限公司", position: "外贸经理", email: "ouyangcx@demo.com", address: "青岛市市南区香港中路"),
        SampleReceivedCard(name: "彭浩然", phone: "13800010025", organization: "鼎新制造有限公司", position: "生产主管", email: "penghr@demo.com", address: "东莞市松山湖科技产业园"),
        SampleReceivedCard(name: "秦书瑶", phone: "13800010026", organization: "星耀游戏有限公司", position: "游戏策划", email: "qinsy@demo.com", address: "上海市徐汇区漕河泾开发区"),
        SampleReceivedCard(name: "任子墨", phone: "13800010027", organization: "智云网络科技有限公司", position: "网络工程师", email: "renzm@demo.com", address: "北京市亦庄经济开发区"),
        SampleReceivedCard(name: "孙若彤", phone: "13800010028", organization: "优家家居有限公司", position: "产品设计师", email: "sunrt@demo.com", address: "佛山市顺德区北滘镇"),
        SampleReceivedCard(name: "唐一鸣", phone: "13800010029", organization: "博远建筑设计院", position: "建筑设计师", email: "tangym@demo.com", address: "成都市锦江区东大街100号"),
        SampleReceivedCard(name: "王欣妍", phone: "13800010030", organization: "创想科技集团", position: "人力资源总监", email: "wangxy@demo.com", address: "上海市静安区南京西路1266号")
    ]
}
