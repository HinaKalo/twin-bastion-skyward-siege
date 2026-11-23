class_name StoryData
extends RefCounted
## Story script for Twin Bastion TD.
## Premise: 300 years ago two guardians sealed the Obsidian Demon and became the blue and red stars.
## Each generation sends two people to hold the twin bastions east of the capital; the rule is that
## neither tower may fall. The red star has started to dim, and the monsters are on the move.
## Lines are {"who": speaker_id, "text": ...}. "narrator" lines render as full-screen narration.

const SPEAKERS: Dictionary = {
	"narrator": {"name": "", "color": Color(0.90, 0.92, 1.0)},
	"lan": {"name": "岚 · 苍穹游侠", "color": Color(0.36, 0.82, 1.0), "sprite": "hero_p1", "owner": 1, "side": "left"},
	"he": {"name": "赫 · 绯红圣骑", "color": Color(1.0, 0.44, 0.50), "sprite": "hero_p2", "owner": 2, "side": "right"},
	"ge": {"name": "葛伯 · 守备官", "color": Color(1.0, 0.86, 0.38), "sprite": "elder", "owner": 0, "side": "left"},
	"grosh": {"name": "格罗什 · 哥布林督军", "color": Color(0.70, 0.95, 0.45), "sprite": "boss_warlord", "owner": 0, "side": "right"},
	"obsidian": {"name": "黑曜魔王", "color": Color(0.85, 0.55, 1.0), "sprite": "boss_obsidian", "owner": 0, "side": "right"},
}

const PROLOGUE: Array[Dictionary] = [
	{"who": "narrator", "text": "三百年前的一个冬天，黑曜魔王从深渊里爬出来，烧掉了半个苍穹王国。"},
	{"who": "narrator", "text": "两个守卫把它打了回去，拿自己的命堵住了裂口。从那以后，夜空里多了一蓝一红两颗星。老人们说，那就是他们俩。"},
	{"who": "narrator", "text": "王城东边的两座塔，是他们当年守过的地方，后来叫双子堡垒。每一代挑两个人去守塔。规矩只有一条：哪座塔都不能丢。"},
	{"who": "narrator", "text": "上个月，红星连着暗了三个晚上。"},
	{"who": "narrator", "text": "没过几天，哥布林成群往王城这边跑。看那跑法，不太像是来打仗的。"},
	{"who": "narrator", "text": "这一代的守塔人今天刚到：游侠岚，圣骑赫。两个人以前没见过面。"},
]

const EPILOGUE: Array[Dictionary] = [
	{"who": "narrator", "text": "魔王倒下时没出声。它的壳一块块裂开，沉回了深渊。"},
	{"who": "narrator", "text": "回廊顶上的裂口慢慢合拢。外面传来葛伯的喊声，他带着人一路找了过来。"},
	{"who": "narrator", "text": "那天晚上，两颗星一起亮着，一整夜没闪。"},
	{"who": "lan", "text": "明天还得回塔里。"},
	{"who": "he", "text": "嗯。你北边，我南边。"},
]

const STAGES: Dictionary = {
	"stage_1_twin_bridge": {
		"briefing": "哥布林督军格罗什要带兵过翡翠河。河上只有南北两座桥，你们一人守一座。",
		"intro": [
			{"who": "ge", "text": "两位，哥布林已经到对岸了。格罗什的旗子也插着。"},
			{"who": "lan", "text": "上任第一天就开打？行吧，我守北桥，南边交给你。"},
			{"who": "he", "text": "好。南桥后面有座磨坊，别让它们烧了。"},
			{"who": "ge", "text": "塔基上发光的符文是建塔的位置。谁缺钱就互相匀一点，守塔人一直是这么干的。"},
		],
		"barks": {
			0: {"who": "lan", "text": "来了。别让它们碰到桥板。"},
			2: {"who": "he", "text": "天上那些是蝙蝠，我的卫兵够不着，交给你。"},
			3: {"who": "lan", "text": "那几个拿弓的会射塔，塔冒烟了就修一下。"},
			5: {"who": "ge", "text": "督军亲自过河了！"},
		},
		"bosses": {"boss_warlord": "两个小崽子也敢守塔？上一代守塔的，骨头还在河底躺着。"},
		"win": "格罗什逃回了对岸。他的兵走的时候一直回头往东看，看着不像是在怕你们。",
		"lose": "桥丢了，哥布林冲进了村子。葛伯把你们拖回塔里，只说了一句：“再来。”",
	},
	"stage_2_rift_cross": {
		"briefing": "东边的地裂开了，缝里往外冒紫光。萨满在裂口施法，盾卫护着它们往外冲。",
		"intro": [
			{"who": "he", "text": "我审了一个俘虏。他说裂谷里有东西在追它们。"},
			{"who": "lan", "text": "所以它们是往我们这边逃，路上顺手抢一把？"},
			{"who": "he", "text": "差不多。麻烦的是它们分四路进来，到中间两个路口才撞到一块。"},
			{"who": "lan", "text": "那就在路口等着。萨满先打，被它们治好的哥布林，我可不想射第二遍。"},
		],
		"barks": {
			0: {"who": "he", "text": "北边归你，南边归我。"},
			2: {"who": "lan", "text": "盾卫举着盾，箭射上去跟挠痒似的，得用法师塔砸。"},
			4: {"who": "he", "text": "扛木头那个巨魔是冲着塔来的，别让它贴到塔边。"},
			5: {"who": "lan", "text": "天上那些红蝙蝠背着火药，会直接往塔上撞！"},
			6: {"who": "lan", "text": "格罗什又来了，还带了个兄弟。"},
		},
		"bosses": {"boss_warlord": "上次那座桥，是我让给你们的。"},
		"win": "裂缝没有合上。赫用剑尖探了探，拔出来时剑尖裹了一层黑壳，摸着像烧过的玻璃。",
		"lose": "萨满把伤兵一个个治了回去，防线被一点点磨穿。",
	},
	"stage_3_royal_siege": {
		"briefing": "裂缝一直裂到了王城脚下。五条路同时来敌人，城门外站着一个很大的黑影。",
		"intro": [
			{"who": "ge", "text": "城门外那个影子……我小时候在神殿壁画上见过。"},
			{"who": "he", "text": "魔王应该在封印底下。"},
			{"who": "lan", "text": "那就是封印漏了。红星这阵子一直在闪。"},
			{"who": "ge", "text": "五条路都有人往城门冲。你们顶住，城里的人才走得掉。"},
		],
		"barks": {
			0: {"who": "ge", "text": "西大道最短，别让它空着。"},
			2: {"who": "he", "text": "影子里那些跑得快的，别让它们摸到城门。"},
			3: {"who": "lan", "text": "石头鸟！箭打上去只冒火星，换法师塔。"},
			7: {"who": "ge", "text": "是它……它真出来了。"},
		},
		"bosses": {"boss_warlord": "我说了，我是被逼的！", "boss_obsidian": "三百年了，守塔的还是两个人。"},
		"win": "黑影散了，地上只剩一块黑曜石。葛伯说北边雪原有座老守卫的墓，封印的另一半刻在那儿。",
		"lose": "城门被撞开了。远处，红星又暗了一下。",
	},
	"stage_4_frost_trail": {
		"briefing": "去北边雪原找老守卫的墓。主路绕着山一圈圈走，冰霜巨像守在墓前。",
		"intro": [
			{"who": "lan", "text": "我老家就在这片雪原。墓的事我外婆讲过，我一直当是哄小孩的。"},
			{"who": "he", "text": "她怎么讲的？"},
			{"who": "lan", "text": "两个人一起把手按在碑上，星星就会亮。"},
			{"who": "he", "text": "那得先活着走到碑前。"},
		],
		"barks": {
			0: {"who": "lan", "text": "这条路绕得厉害，敌人要走很久，寒冰塔能多冻它们几轮。"},
			3: {"who": "he", "text": "风里有东西在叫。"},
			6: {"who": "lan", "text": "格罗什跟到雪原来了？它也在逃。"},
			7: {"who": "he", "text": "它过来了。塔别挤一块，它吼一声能冻住一片。"},
		},
		"bosses": {"boss_warlord": "这儿冷死了……让开！", "boss_frost_colossus": "（墓前的冰层裂开，冰霜巨像站了起来。）"},
		"win": "碑上刻着两只手印。你们一人按住一只，蓝星亮了，红星也亮了，可没过多久红星的光又开始抖。碑底有一行小字：封印的根在深渊回廊。",
		"lose": "风雪把路埋了。你们退回山脚，等雪停了再上。",
	},
	"stage_5_abyss_corridor": {
		"briefing": "深渊回廊就是三百年前那道裂口。魔王醒了，回廊中间那道裂隙随时会开。守到双星重新连上为止。",
		"intro": [
			{"who": "he", "text": "岚，要是今天回不去……"},
			{"who": "lan", "text": "别说。你那套话留着回去讲给葛伯听。"},
			{"who": "he", "text": "……我是想说，你的箭是我见过最准的。"},
			{"who": "lan", "text": "知道了。守好你那边。"},
		],
		"barks": {
			0: {"who": "lan", "text": "三条廊道，分开守，但别离太远。"},
			3: {"who": "he", "text": "回廊中间裂开了，有东西从里面出来！"},
			6: {"who": "he", "text": "冰霜巨像也在这儿？深渊把它们全叫醒了。"},
			8: {"who": "lan", "text": "后面还有个更大的。"},
			9: {"who": "he", "text": "它来了。"},
		},
		"bosses": {
			"boss_warlord": "别看我，我也是被赶进来的！",
			"boss_frost_colossus": "（回廊深处传来冰层碎裂的声音。）",
			"boss_obsidian": "又是你们。这回我把门开大了。",
			"boss_obsidian_awakened": "上一对守塔的也站在这儿。后来，他们成了天上的两盏灯。",
		},
		"win": "",
		"lose": "你们被逼退到回廊口。双星还亮着，还来得及。",
	},
}


static func get_stage(stage_id: String) -> Dictionary:
	return STAGES.get(stage_id, {})


static func get_bark(stage_id: String, wave_index: int) -> Dictionary:
	var barks: Dictionary = get_stage(stage_id).get("barks", {})
	return barks.get(wave_index, {})


static func get_boss_line(stage_id: String, enemy_id: String) -> String:
	var bosses: Dictionary = get_stage(stage_id).get("bosses", {})
	return str(bosses.get(enemy_id, ""))


static func speaker(who: String) -> Dictionary:
	return SPEAKERS.get(who, SPEAKERS["narrator"])


static func is_final_stage(stage_id: String) -> bool:
	return stage_id == "stage_5_abyss_corridor"
