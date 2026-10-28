extends RefCounted
## 规则判定：照搬 mahjong.js 的 isStandardWin / isSevenPairs / isDragonSevenPairs /
## isAllTriplets / evaluate / waitsFor
## 牌用 0..33 的整数：0-8 万 1-9、9-17 筒 1-9、18-26 条 1-9、27-30 东南西北、31-33 中發白

static func counts(tiles: Array) -> Dictionary:
	var c := {}
	for t in tiles:
		c[t] = int(c.get(t, 0)) + 1
	return c

## 把 counts 拆成 need 组（刻子/顺子），全部拆完为 true
static func decompose(c: Dictionary, need: int) -> bool:
	if need == 0:
		return c.is_empty()
	var keys := c.keys()
	keys.sort()
	for k in keys:
		# 刻子
		if int(c[k]) >= 3:
			var n := c.duplicate()
			n[k] = int(n[k]) - 3
			if int(n[k]) == 0:
				n.erase(k)
			if decompose(n, need - 1):
				return true
		# 顺子（仅数字牌，且不能跨花色）
		if k < 27 and k % 9 <= 6:
			if int(c.get(k + 1, 0)) >= 1 and int(c.get(k + 2, 0)) >= 1:
				var m := c.duplicate()
				for kk in [k, k + 1, k + 2]:
					m[kk] = int(m[kk]) - 1
					if int(m[kk]) == 0:
						m.erase(kk)
				if decompose(m, need - 1):
					return true
		break   # 只从最小的那张牌开始试，避免重复枚举
	return false

static func is_standard_win(concealed: Array, meld_count: int) -> bool:
	if concealed.size() + meld_count * 3 != 14:
		return false
	var need := (concealed.size() - 2) / 3
	if need < 0:
		return false
	var c := counts(concealed)
	for k in c.keys():
		if int(c[k]) >= 2:
			var n := c.duplicate()
			n[k] = int(n[k]) - 2
			if int(n[k]) == 0:
				n.erase(k)
			if decompose(n, need):
				return true
	return false

static func is_seven_pairs(concealed: Array) -> bool:
	if concealed.size() != 14:
		return false
	var c := counts(concealed)
	for k in c.keys():
		if int(c[k]) % 2 != 0:
			return false
	return true

static func is_dragon_seven(concealed: Array) -> bool:
	if not is_seven_pairs(concealed):
		return false
	var c := counts(concealed)
	for k in c.keys():
		if int(c[k]) == 4:
			return true
	return false

static func is_all_triplets(concealed: Array, melds: Array) -> bool:
	for m in melds:
		if m["type"] != "peng" and m["type"] != "gang":
			return false
	if concealed.size() != 14 - melds.size() * 3:
		return false
	var c := counts(concealed)
	var triplets := 0
	var pairs := 0
	for k in c.keys():
		if int(c[k]) == 3:
			triplets += 1
		elif int(c[k]) == 2:
			pairs += 1
		else:
			return false
	return pairs == 1 and triplets + melds.size() == 4

## 返回 {} 表示不成牌；否则 { tier, name }
static func evaluate(concealed: Array, melds: Array) -> Dictionary:
	var n := concealed.size()
	var m := melds.size()
	if n + m * 3 != 14:
		return {}
	if m == 0 and is_seven_pairs(concealed):
		if is_dragon_seven(concealed):
			return { "tier": "biggest", "name": "七对 · 龙七对" }
		return { "tier": "bigger", "name": "七对" }
	if not is_standard_win(concealed, m):
		return {}
	if n == 2 and m == 4:
		return { "tier": "bigger", "name": "大吊车" }
	if is_all_triplets(concealed, melds):
		return { "tier": "big", "name": "碰碰胡" }
	return { "tier": "small", "name": "小胡" }

## 听牌：13-3m 张时，返回所有能成牌的牌
static func waits(concealed: Array, melds: Array) -> Array:
	var out: Array = []
	if (concealed.size() + melds.size() * 3) % 3 != 1:
		return out
	for t in range(34):
		var used := 0
		for x in concealed:
			if x == t:
				used += 1
		for mm in melds:
			for x in mm["tiles"]:
				if x == t:
					used += 1
		if used >= 4:
			continue
		var probe: Array = concealed.duplicate()
		probe.append(t)
		if not evaluate(probe, melds).is_empty():
			out.append(t)
	return out

## 向听数：0=听牌，-1=已和牌。支持普通四组一对与七对。
## 可传入共享 memo，让同回合多个候选弃牌复用中间状态。
static func shanten(concealed: Array, melds: Array, memo: Variant = null) -> int:
	var cache: Dictionary = memo if memo is Dictionary else {}
	var standard := _standard_shanten(counts(concealed), melds.size(), cache)
	var result := standard
	if melds.is_empty():
		result = mini(result, _seven_pairs_shanten(concealed))
	return result

static func _standard_shanten(counts: Dictionary, meld_count: int, memo: Dictionary) -> int:
	var max_blocks := maxi(0, 4 - meld_count)
	var best := _best_block_score(counts, 0, 0, 0, max_blocks, memo)
	return 8 - meld_count * 2 - best

static func _seven_pairs_shanten(concealed: Array) -> int:
	var c := counts(concealed)
	var pairs := 0
	var kinds := 0
	for value in c.values():
		kinds += 1
		if int(value) >= 2:
			pairs += 1
	return 6 - pairs + maxi(0, 7 - kinds)

static func _without(c: Dictionary, t: int, n: int) -> Dictionary:
	var out := c.duplicate()
	out[t] = int(out[t]) - n
	if int(out[t]) == 0:
		out.erase(t)
	return out

## 返回 2*刻顺组 + 搭子 + 对子头的最大加权块数。
static func _best_block_score(c: Dictionary, sets: int, taatsu: int, pair: int, max_blocks: int, memo: Dictionary) -> int:
	var key := _state_key(c, sets, taatsu, pair, max_blocks)
	if memo.has(key):
		return int(memo[key])
	var keys := c.keys()
	if keys.is_empty():
		var empty_score := sets * 2 + taatsu + pair
		memo[key] = empty_score
		return empty_score
	keys.sort()
	var t := int(keys[0])
	var best := sets * 2 + taatsu + pair
	var blocks := sets + taatsu
	var probe: Dictionary

	# 刻子
	if int(c[t]) >= 3 and blocks < max_blocks:
		probe = _without(c, t, 3)
		best = maxi(best, _best_block_score(probe, sets + 1, taatsu, pair, max_blocks, memo))
	# 顺子
	if t < 27 and t % 9 <= 6 and int(c.get(t + 1, 0)) > 0 and int(c.get(t + 2, 0)) > 0 and blocks < max_blocks:
		probe = c.duplicate()
		for k in [t, t + 1, t + 2]:
			probe[k] = int(probe[k]) - 1
			if int(probe[k]) == 0:
				probe.erase(k)
		best = maxi(best, _best_block_score(probe, sets + 1, taatsu, pair, max_blocks, memo))
	# 对子头
	if pair == 0 and int(c[t]) >= 2:
		probe = _without(c, t, 2)
		best = maxi(best, _best_block_score(probe, sets, taatsu, 1, max_blocks, memo))
	# 对子搭子
	if int(c[t]) >= 2 and blocks < max_blocks:
		probe = _without(c, t, 2)
		best = maxi(best, _best_block_score(probe, sets, taatsu + 1, pair, max_blocks, memo))
	# 相邻两面搭子
	if t < 27 and t % 9 <= 7 and int(c.get(t + 1, 0)) > 0 and blocks < max_blocks:
		probe = c.duplicate()
		for k in [t, t + 1]:
			probe[k] = int(probe[k]) - 1
			if int(probe[k]) == 0:
				probe.erase(k)
		best = maxi(best, _best_block_score(probe, sets, taatsu + 1, pair, max_blocks, memo))
	# 隔张搭子
	if t < 27 and t % 9 <= 6 and int(c.get(t + 2, 0)) > 0 and blocks < max_blocks:
		probe = c.duplicate()
		for k in [t, t + 2]:
			probe[k] = int(probe[k]) - 1
			if int(probe[k]) == 0:
				probe.erase(k)
		best = maxi(best, _best_block_score(probe, sets, taatsu + 1, pair, max_blocks, memo))
	# 放弃这张孤张
	probe = _without(c, t, 1)
	best = maxi(best, _best_block_score(probe, sets, taatsu, pair, max_blocks, memo))
	memo[key] = best
	return best

static func _state_key(c: Dictionary, sets: int, taatsu: int, pair: int, max_blocks: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(34)
	for i in range(34):
		bytes[i] = int(c.get(i, 0))
	return "%d%d%d%d:%s" % [max_blocks, sets, taatsu, pair, bytes.hex_encode()]

## 赔付：小胡 2 张/家，大胡 4，七对 8，龙七对 16
static func payout(tier: String, stake: int) -> Dictionary:
	var tiles := 2
	match tier:
		"big":
			tiles = 4
		"bigger":
			tiles = 8
		"biggest":
			tiles = 16
	return { "tiles": tiles, "per": tiles * stake, "total": tiles * stake * 3 }
