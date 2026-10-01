import CryptoKit
import Foundation

/// Original toddler phrases for the built-in library. Not copied from Collins, COBUILD, or graded word lists.
public enum SeedLibrary {
    public static let phrases: [LibraryPhrase] = rows.enumerated().map { index, row in
        LibraryPhrase(
            id: stableID(row.english),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            english: row.english,
            chinese: row.chinese,
            scene: row.scene,
            keywords: row.keywords,
            source: "seed"
        )
    }

    public static func stableID(_ english: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("echo101.seed.\(english)".utf8)))
        let bytes = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5],
            (digest[6] & 0x0F) | 0x40, digest[7],
            (digest[8] & 0x3F) | 0x80, digest[9],
            digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: bytes)
    }

    private struct Row {
        var english: String
        var chinese: String
        var scene: String
        var keywords: [String]
    }

    private static let rows: [Row] = [
        Row(english: "Time to eat.", chinese: "该吃饭了。", scene: "吃饭", keywords: ["吃饭", "吃饭了", "该吃饭"]),
        Row(english: "Open your mouth.", chinese: "张开嘴。", scene: "吃饭", keywords: ["张嘴", "张开嘴"]),
        Row(english: "One more bite.", chinese: "再吃一口。", scene: "吃饭", keywords: ["再吃一口", "再吃一点"]),
        Row(english: "So yummy.", chinese: "真好吃。", scene: "吃饭", keywords: ["好吃", "真好吃"]),
        Row(english: "All done.", chinese: "吃完了。", scene: "吃饭", keywords: ["吃完了", "吃好了"]),
        Row(english: "Let's wash our hands.", chinese: "我们去洗手。", scene: "吃饭", keywords: ["洗手", "洗洗手", "把手洗"]),
        Row(english: "Water, please.", chinese: "请给我水。", scene: "吃饭", keywords: ["喝水", "要水", "给我水"]),
        Row(english: "Milk, please.", chinese: "请给我牛奶。", scene: "吃饭", keywords: ["牛奶", "喝牛奶"]),
        Row(english: "Are you hungry?", chinese: "你饿了吗？", scene: "吃饭", keywords: ["饿了", "肚子饿"]),
        Row(english: "Are you thirsty?", chinese: "你渴了吗？", scene: "吃饭", keywords: ["渴了", "口渴"]),
        Row(english: "Blow on it.", chinese: "吹一吹。", scene: "吃饭", keywords: ["吹一吹", "烫"]),
        Row(english: "Use your spoon.", chinese: "用勺子。", scene: "吃饭", keywords: ["勺子", "用勺子"]),

        Row(english: "Bath time.", chinese: "该洗澡了。", scene: "洗澡", keywords: ["洗澡", "洗澡了"]),
        Row(english: "The water is warm.", chinese: "水是温的。", scene: "洗澡", keywords: ["水温", "温水"]),
        Row(english: "Wash your hair.", chinese: "洗洗头。", scene: "洗澡", keywords: ["洗头", "洗洗头"]),
        Row(english: "Close your eyes.", chinese: "闭上眼睛。", scene: "洗澡", keywords: ["闭眼", "闭上眼睛"]),
        Row(english: "Rinse, rinse.", chinese: "冲一冲。", scene: "洗澡", keywords: ["冲一冲", "冲洗"]),
        Row(english: "Dry off.", chinese: "擦干。", scene: "洗澡", keywords: ["擦干", "擦一擦"]),
        Row(english: "Put on your pajamas.", chinese: "穿上睡衣。", scene: "洗澡", keywords: ["睡衣"]),
        Row(english: "You smell so clean.", chinese: "洗得好干净。", scene: "洗澡", keywords: ["干净", "好香"]),

        Row(english: "Let's get dressed.", chinese: "我们穿衣服。", scene: "穿衣", keywords: ["穿衣服", "穿衣"]),
        Row(english: "Arms up.", chinese: "举起手。", scene: "穿衣", keywords: ["举手", "举起手", "手举起来"]),
        Row(english: "Put on your shirt.", chinese: "穿上衣服。", scene: "穿衣", keywords: ["穿上衣服", "上衣"]),
        Row(english: "Put on your pants.", chinese: "穿上裤子。", scene: "穿衣", keywords: ["裤子", "穿裤子"]),
        Row(english: "Put on your socks.", chinese: "穿上袜子。", scene: "穿衣", keywords: ["袜子", "穿袜子"]),
        Row(english: "Put on your shoes.", chinese: "穿上鞋子。", scene: "穿衣", keywords: ["鞋子", "穿鞋"]),
        Row(english: "Zip it up.", chinese: "拉上拉链。", scene: "穿衣", keywords: ["拉链", "拉上"]),
        Row(english: "This one or that one?", chinese: "这件还是那件？", scene: "穿衣", keywords: ["这件", "哪件"]),

        Row(english: "Let's go outside.", chinese: "我们出门。", scene: "出门", keywords: ["出门", "出去", "出去玩"]),
        Row(english: "Hold my hand.", chinese: "拉着我的手。", scene: "出门", keywords: ["拉手", "牵手", "拉着我"]),
        Row(english: "Look both ways.", chinese: "左右看一看。", scene: "出门", keywords: ["看车", "左右看", "过马路"]),
        Row(english: "Wait for me.", chinese: "等我一下。", scene: "出门", keywords: ["等一下", "等等我"]),
        Row(english: "Stay close.", chinese: "跟紧一点。", scene: "出门", keywords: ["跟紧", "别走远", "别跑远"]),
        Row(english: "Time to go home.", chinese: "该回家了。", scene: "出门", keywords: ["回家", "回家了"]),
        Row(english: "Get in the car.", chinese: "上车。", scene: "出门", keywords: ["上车", "坐车"]),
        Row(english: "Buckle up.", chinese: "系好安全带。", scene: "出门", keywords: ["安全带", "系上"]),
        Row(english: "Wave bye-bye.", chinese: "挥手再见。", scene: "出门", keywords: ["再见", "拜拜", "挥手"]),
        Row(english: "Put on your hat.", chinese: "戴上帽子。", scene: "出门", keywords: ["帽子", "戴帽子"]),

        Row(english: "Your turn.", chinese: "轮到你了。", scene: "玩具", keywords: ["轮到你", "该你了"]),
        Row(english: "My turn.", chinese: "轮到我了。", scene: "玩具", keywords: ["轮到我", "该我了"]),
        Row(english: "Build it up.", chinese: "搭高一点。", scene: "玩具", keywords: ["搭积木", "积木", "搭高"]),
        Row(english: "Knock it down.", chinese: "推倒。", scene: "玩具", keywords: ["推倒", "倒了"]),
        Row(english: "Roll the ball.", chinese: "把球滚过来。", scene: "玩具", keywords: ["球", "滚球"]),
        Row(english: "Vroom vroom.", chinese: "汽车呜呜开。", scene: "玩具", keywords: ["小汽车", "汽车", "开车"]),
        Row(english: "Read a book.", chinese: "一起看书。", scene: "玩具", keywords: ["看书", "读书", "绘本"]),
        Row(english: "Put the toys away.", chinese: "把玩具收起来。", scene: "玩具", keywords: ["收玩具", "收拾玩具"]),
        Row(english: "Share with me.", chinese: "分给我一点。", scene: "玩具", keywords: ["分享", "分给我"]),
        Row(english: "Be gentle.", chinese: "轻轻地。", scene: "玩具", keywords: ["轻轻", "轻一点"]),

        Row(english: "Time for bed.", chinese: "该睡觉了。", scene: "睡觉", keywords: ["睡觉", "睡觉了", "上床"]),
        Row(english: "Lie down.", chinese: "躺下。", scene: "睡觉", keywords: ["躺下", "躺好"]),
        Row(english: "Close your eyes and sleep.", chinese: "闭上眼睛睡觉。", scene: "睡觉", keywords: ["闭眼睡觉", "睡觉吧"]),
        Row(english: "Sweet dreams.", chinese: "做个好梦。", scene: "睡觉", keywords: ["好梦", "晚安"]),
        Row(english: "Good night.", chinese: "晚安。", scene: "睡觉", keywords: ["晚安"]),
        Row(english: "I love you.", chinese: "我爱你。", scene: "睡觉", keywords: ["爱你", "我爱你"]),
        Row(english: "One more story.", chinese: "再讲一个故事。", scene: "睡觉", keywords: ["故事", "再讲一个"]),
        Row(english: "Turn off the light.", chinese: "关灯。", scene: "睡觉", keywords: ["关灯", "灯关了"]),

        Row(english: "Don't touch that.", chinese: "不要碰那个。", scene: "安全", keywords: ["不要碰", "别碰", "不能碰"]),
        Row(english: "Hot! Don't touch.", chinese: "烫！不要摸。", scene: "安全", keywords: ["烫", "好烫", "别摸"]),
        Row(english: "Stop.", chinese: "停下来。", scene: "安全", keywords: ["停下", "停下来", "站住"]),
        Row(english: "Come here.", chinese: "过来。", scene: "安全", keywords: ["过来", "到这里"]),
        Row(english: "Be careful.", chinese: "小心。", scene: "安全", keywords: ["小心", "当心"]),
        Row(english: "That's not safe.", chinese: "那个不安全。", scene: "安全", keywords: ["危险", "不安全"]),
        Row(english: "Sit down, please.", chinese: "请坐下。", scene: "安全", keywords: ["坐下", "坐好"]),
        Row(english: "No running.", chinese: "不要跑。", scene: "安全", keywords: ["不要跑", "别跑"]),

        Row(english: "Good morning.", chinese: "早上好。", scene: "日常", keywords: ["早上好", "早安"]),
        Row(english: "Hello.", chinese: "你好。", scene: "日常", keywords: ["你好", "哈啰"]),
        Row(english: "Thank you.", chinese: "谢谢。", scene: "日常", keywords: ["谢谢", "感谢"]),
        Row(english: "You're welcome.", chinese: "不客气。", scene: "日常", keywords: ["不客气"]),
        Row(english: "Please.", chinese: "请。", scene: "日常", keywords: ["请"]),
        Row(english: "I'm sorry.", chinese: "对不起。", scene: "日常", keywords: ["对不起", "抱歉"]),
        Row(english: "It's okay.", chinese: "没关系。", scene: "日常", keywords: ["没关系", "没事"]),
        Row(english: "Look at that.", chinese: "你看那个。", scene: "日常", keywords: ["你看", "看那个"]),
        Row(english: "What is this?", chinese: "这是什么？", scene: "日常", keywords: ["这是什么", "这是啥"]),
        Row(english: "I see you.", chinese: "我看见你了。", scene: "日常", keywords: ["看见你", "我看到你"]),
        Row(english: "Come help me.", chinese: "来帮帮我。", scene: "日常", keywords: ["帮忙", "帮我"]),
        Row(english: "Let's clean up.", chinese: "我们一起收拾。", scene: "日常", keywords: ["收拾", "整理"]),
        Row(english: "Open the door.", chinese: "开门。", scene: "日常", keywords: ["开门", "打开门"]),
        Row(english: "Close the door.", chinese: "关门。", scene: "日常", keywords: ["关门", "把门关上"]),
        Row(english: "Where is it?", chinese: "它在哪里？", scene: "日常", keywords: ["在哪里", "在哪儿"]),
        Row(english: "Here it is.", chinese: "在这里。", scene: "日常", keywords: ["在这里", "在这儿"]),
        Row(english: "Good job.", chinese: "做得好。", scene: "日常", keywords: ["做得好", "真棒", "好厉害"]),
        Row(english: "Try again.", chinese: "再试一次。", scene: "日常", keywords: ["再试一次", "再来一次"])
    ]
}
