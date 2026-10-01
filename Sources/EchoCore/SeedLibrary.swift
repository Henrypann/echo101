import Foundation

/// Everyday toddler sentences written for this app. Not a word list from any publisher.
public enum SeedLibrary {
    public static func make(now: Date = Date()) -> [LibraryPhrase] {
        entries.enumerated().map { index, entry in
            LibraryPhrase(
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                chinese: entry.chinese,
                english: entry.english,
                scene: entry.scene,
                keywords: entry.keywords,
                source: "seed")
        }
    }

    private struct Entry {
        var scene: String
        var chinese: String
        var english: String
        var keywords: [String]
    }

    private static let entries: [Entry] = [
        Entry(scene: "吃饭", chinese: "吃饭了", english: "Time to eat.", keywords: ["吃饭", "开饭", "吃饭了"]),
        Entry(scene: "吃饭", chinese: "我饿了", english: "I am hungry.", keywords: ["饿", "肚子饿", "我饿了"]),
        Entry(scene: "吃饭", chinese: "我渴了", english: "I am thirsty.", keywords: ["渴", "我渴了"]),
        Entry(scene: "吃饭", chinese: "我想喝水", english: "I want water.", keywords: ["喝水", "水", "我想喝水"]),
        Entry(scene: "吃饭", chinese: "我想喝牛奶", english: "I want milk.", keywords: ["牛奶", "喝奶", "我想喝牛奶"]),
        Entry(scene: "吃饭", chinese: "再来一点", english: "More, please.", keywords: ["再来", "还要", "再来一点"]),
        Entry(scene: "吃饭", chinese: "我吃饱了", english: "I am full.", keywords: ["吃饱", "饱了", "我吃饱了"]),
        Entry(scene: "吃饭", chinese: "好吃", english: "This is yummy.", keywords: ["好吃", "真好吃"]),
        Entry(scene: "吃饭", chinese: "慢慢吃", english: "Eat slowly.", keywords: ["慢慢吃", "别急"]),
        Entry(scene: "吃饭", chinese: "擦擦嘴巴", english: "Wipe your mouth.", keywords: ["擦嘴", "嘴巴", "擦擦嘴巴"]),
        Entry(scene: "洗澡", chinese: "该洗澡了", english: "Time for a bath.", keywords: ["洗澡", "该洗澡了"]),
        Entry(scene: "洗澡", chinese: "水热了", english: "The water is warm.", keywords: ["水热", "水温"]),
        Entry(scene: "洗澡", chinese: "洗洗手", english: "Wash your hands.", keywords: ["洗手", "洗洗手"]),
        Entry(scene: "洗澡", chinese: "洗洗脸", english: "Wash your face.", keywords: ["洗脸", "洗洗脸"]),
        Entry(scene: "洗澡", chinese: "刷刷牙", english: "Brush your teeth.", keywords: ["刷牙", "刷刷牙"]),
        Entry(scene: "洗澡", chinese: "冲干净", english: "Rinse it off.", keywords: ["冲洗", "冲干净"]),
        Entry(scene: "洗澡", chinese: "擦干身体", english: "Dry your body.", keywords: ["擦干", "毛巾"]),
        Entry(scene: "穿衣", chinese: "穿衣服", english: "Put on your shirt.", keywords: ["穿衣服", "上衣"]),
        Entry(scene: "穿衣", chinese: "穿裤子", english: "Put on your pants.", keywords: ["裤子", "穿裤子"]),
        Entry(scene: "穿衣", chinese: "穿鞋子", english: "Put on your shoes.", keywords: ["鞋子", "穿鞋", "穿鞋子"]),
        Entry(scene: "穿衣", chinese: "穿袜子", english: "Put on your socks.", keywords: ["袜子", "穿袜子"]),
        Entry(scene: "穿衣", chinese: "戴帽子", english: "Put on your hat.", keywords: ["帽子", "戴帽子"]),
        Entry(scene: "穿衣", chinese: "拉上拉链", english: "Zip it up.", keywords: ["拉链", "拉上拉链"]),
        Entry(scene: "穿衣", chinese: "太热了", english: "It is too hot.", keywords: ["热", "太热了"]),
        Entry(scene: "穿衣", chinese: "太冷了", english: "It is too cold.", keywords: ["冷", "太冷了"]),
        Entry(scene: "出门", chinese: "我们出门", english: "Let's go out.", keywords: ["出门", "出去", "我们出门"]),
        Entry(scene: "出门", chinese: "回家了", english: "Time to go home.", keywords: ["回家", "回家了"]),
        Entry(scene: "出门", chinese: "坐车", english: "We ride in the car.", keywords: ["坐车", "汽车", "上车"]),
        Entry(scene: "出门", chinese: "等一等", english: "Wait a minute.", keywords: ["等等", "等一等", "等一下"]),
        Entry(scene: "出门", chinese: "拉着我的手", english: "Hold my hand.", keywords: ["拉手", "牵手", "拉着我的手"]),
        Entry(scene: "出门", chinese: "看一看", english: "Look at this.", keywords: ["看", "看看", "看一看"]),
        Entry(scene: "出门", chinese: "走这边", english: "Walk this way.", keywords: ["这边", "走这边"]),
        Entry(scene: "玩具", chinese: "玩小汽车", english: "Play with the car.", keywords: ["小汽车", "汽车", "玩车"]),
        Entry(scene: "玩具", chinese: "搭积木", english: "Stack the blocks.", keywords: ["积木", "搭积木"]),
        Entry(scene: "玩具", chinese: "捡起来", english: "Pick it up.", keywords: ["捡", "捡起来"]),
        Entry(scene: "玩具", chinese: "放进盒子", english: "Put it in the box.", keywords: ["盒子", "放进去", "放进盒子"]),
        Entry(scene: "玩具", chinese: "收玩具", english: "Put the toys away.", keywords: ["收玩具", "收拾"]),
        Entry(scene: "玩具", chinese: "轮到你了", english: "It is your turn.", keywords: ["轮到你", "该你了"]),
        Entry(scene: "玩具", chinese: "我们一起玩", english: "Let's play together.", keywords: ["一起玩", "我们一起玩"]),
        Entry(scene: "玩具", chinese: "轻轻地玩", english: "Play gently.", keywords: ["轻轻", "轻轻地玩"]),
        Entry(scene: "睡觉", chinese: "该睡觉了", english: "Time for bed.", keywords: ["睡觉", "该睡觉了", "晚安"]),
        Entry(scene: "睡觉", chinese: "躺下来", english: "Lie down.", keywords: ["躺下", "躺下来"]),
        Entry(scene: "睡觉", chinese: "盖好被子", english: "Pull up the blanket.", keywords: ["被子", "盖被子", "盖好被子"]),
        Entry(scene: "睡觉", chinese: "关灯", english: "Turn off the light.", keywords: ["关灯", "灯"]),
        Entry(scene: "睡觉", chinese: "闭上眼睛", english: "Close your eyes.", keywords: ["闭眼", "闭上眼睛"]),
        Entry(scene: "睡觉", chinese: "我爱你", english: "I love you.", keywords: ["爱你", "我爱你"]),
        Entry(scene: "睡觉", chinese: "做个好梦", english: "Sweet dreams.", keywords: ["好梦", "做梦"]),
        Entry(scene: "安全", chinese: "不要碰", english: "Don't touch that.", keywords: ["别碰", "不要碰", "不能碰"]),
        Entry(scene: "安全", chinese: "危险", english: "That is not safe.", keywords: ["危险", "不安全"]),
        Entry(scene: "安全", chinese: "停下来", english: "Stop.", keywords: ["停下", "停下来", "站住"]),
        Entry(scene: "安全", chinese: "慢慢走", english: "Walk slowly.", keywords: ["慢慢走", "慢点"]),
        Entry(scene: "安全", chinese: "坐好", english: "Sit down.", keywords: ["坐", "坐好", "坐下"]),
        Entry(scene: "安全", chinese: "热，别碰", english: "It is hot. Don't touch.", keywords: ["烫", "好烫", "别碰"]),
        Entry(scene: "日常", chinese: "早上好", english: "Good morning.", keywords: ["早上", "早上好", "早安"]),
        Entry(scene: "日常", chinese: "谢谢", english: "Thank you.", keywords: ["谢谢", "感谢"]),
        Entry(scene: "日常", chinese: "不客气", english: "You are welcome.", keywords: ["不客气", "不用谢"]),
        Entry(scene: "日常", chinese: "对不起", english: "I am sorry.", keywords: ["对不起", "抱歉"]),
        Entry(scene: "日常", chinese: "请", english: "Please.", keywords: ["请"]),
        Entry(scene: "日常", chinese: "你好", english: "Hello.", keywords: ["你好", "嗨"]),
        Entry(scene: "日常", chinese: "再见", english: "Bye-bye.", keywords: ["再见", "拜拜"]),
        Entry(scene: "日常", chinese: "打开", english: "Open it.", keywords: ["打开", "开"]),
        Entry(scene: "日常", chinese: "关上", english: "Close it.", keywords: ["关上", "关掉", "关"]),
        Entry(scene: "日常", chinese: "给我", english: "Give it to me.", keywords: ["给我", "拿来"]),
        Entry(scene: "日常", chinese: "给你", english: "Here you are.", keywords: ["给你", "拿去"]),
        Entry(scene: "日常", chinese: "我自己来", english: "I can do it.", keywords: ["自己来", "我自己", "我来"]),
        Entry(scene: "日常", chinese: "帮帮我", english: "Please help me.", keywords: ["帮忙", "帮帮我", "帮我"]),
        Entry(scene: "日常", chinese: "好疼", english: "It hurts.", keywords: ["疼", "好疼", "痛"]),
        Entry(scene: "日常", chinese: "我高兴", english: "I am happy.", keywords: ["高兴", "开心", "我高兴"]),
        Entry(scene: "日常", chinese: "我难过", english: "I feel sad.", keywords: ["难过", "伤心"]),
        Entry(scene: "日常", chinese: "看妈妈", english: "Look at me.", keywords: ["看我", "看妈妈", "看爸爸"]),
        Entry(scene: "日常", chinese: "过来", english: "Come here.", keywords: ["过来", "来这里"]),
        Entry(scene: "日常", chinese: "扔垃圾", english: "Put it in the trash.", keywords: ["垃圾", "扔掉", "扔垃圾"]),
        Entry(scene: "日常", chinese: "擦一擦", english: "Wipe it up.", keywords: ["擦", "擦一擦", "擦掉"]),
        Entry(scene: "日常", chinese: "完成了", english: "All done.", keywords: ["好了", "完成", "完成了", "弄好了"])
    ]
}
