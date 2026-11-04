// 두 mock 서버가 공유하는 키워드 기반 "에이전트 판단". LLM 대신 사용자 문장 → 호출할 액션 하나
// tools: 앱이 등록해 보낸 액션 이름 목록. 등록되지 않은 액션은 고르지 않는다 (D2)

const CATEGORIES = { 신발: "shoes", shoes: "shoes", 가방: "bags", bags: "bags", 전체: "all", all: "all" };

export function decide(text, tools) {
  const t = text.toLowerCase();
  const has = (name) => tools.includes(name);

  if (has("cart_clear") && /비워|clear/.test(t)) return { name: "cart_clear", args: {} };

  const id = t.match(/(\d+)\s*번/)?.[1] ?? t.match(/add\s+(\d+)/)?.[1];
  if (has("cart_add") && id && /담아|add/.test(t)) return { name: "cart_add", args: { id: Number(id) } };

  for (const [word, category] of Object.entries(CATEGORIES)) {
    if (has("filter_set") && t.includes(word)) return { name: "filter_set", args: { category } };
  }
  return null;
}

export const HELP = '예: "신발만 보여줘" · "2번 담아줘" · "장바구니 비워줘"';
