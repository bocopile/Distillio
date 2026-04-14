#!/bin/bash
# Distillio — Multi-LLM Cross-Validation Pipeline
# Usage: ./run_pipeline.sh "주제" "대상 수준" "원본 URL or 파일경로(선택)"

set -e

TOPIC="${1:-Kubernetes Operator}"
LEVEL="${2:-DevOps 엔지니어 (3년 이상)}"
SOURCE="${3:-}"
DATE=$(date '+%Y-%m-%d')

# 주제명을 폴더명으로 변환 (공백→언더스코어, 특수문자 제거)
TOPIC_SLUG=$(echo "$TOPIC" | tr ' ' '_' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTDIR="${OUTDIR:-output/${TOPIC_SLUG}/${TIMESTAMP}}"

mkdir -p "$OUTDIR"
echo "$TOPIC"  > "$OUTDIR/meta_topic.txt"
echo "$LEVEL"  > "$OUTDIR/meta_level.txt"
echo "$SOURCE" > "$OUTDIR/meta_source.txt"
echo "$DATE"   > "$OUTDIR/meta_date.txt"

# ─────────────────────────────────────────────
# 공통 헬퍼
# ─────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

check_cli() {
  local name=$1
  command -v "$name" &>/dev/null || die "$name CLI를 찾을 수 없습니다. 설치 확인 후 다시 실행하세요."
}

check_cli claude
check_cli gemini
check_cli codex

# ─────────────────────────────────────────────
# Phase 1: Gemini — 초안 생성
# ─────────────────────────────────────────────
PHASE1_PROMPT="당신은 DevOps/AIOps 전문 교육 콘텐츠 작성자입니다.

[입력 정보]
- 주제: ${TOPIC}
- 대상: ${LEVEL}
- 원본 자료: ${SOURCE:-없음 (자체 지식 활용)}
- 출력 형식: Markdown

[필수 출력 구조 — 반드시 이 순서와 헤더를 지킬 것]

## 1. 개념 (Concept)
- 핵심 개념 정의
- 등장 배경과 해결하는 문제
- 다른 기술과의 비교

## 2. 활용법 (Usage)
- 실제 사용 패턴 (최소 3가지)
- 언제 쓰고 언제 쓰지 말아야 하는지

## 3. 운영 가이드 (Operations Guide)
- 설치 및 초기 설정
- 프로덕션 환경 권장 설정
- 모니터링 포인트

## 4. 트러블슈팅 (Troubleshooting)
- 자주 발생하는 문제 Top 5
- 각 문제의 원인, 증상, 해결책
- 실제 에러 메시지 포함

## 5. 실습 (Hands-on)
- 목표: 읽고 바로 따라할 수 있는 수준
- 사전 요구사항 명시
- 단계별 실행 코드 (복사-붙여넣기 가능)
- 예상 결과 화면

## 6. 참고 자료 (References)
- 공식 문서 링크
- 관련 최신 자료

[출력 규칙]
- 코드 블록은 반드시 언어 명시 (예: \`\`\`bash, \`\`\`yaml)
- 실제 운영에서 검증된 값만 사용, 추정값에는 [추정] 표시
- 원본 자료에 없는 내용 추가 시 [보강] 표시"

log "Phase 1/4 — Gemini: 초안 생성 중..."
gemini --prompt "$PHASE1_PROMPT" > "$OUTDIR/phase1_draft.md" 2>/dev/null
log "Phase 1 완료 → $OUTDIR/phase1_draft.md"

# ─────────────────────────────────────────────
# Phase 2: Claude — 내용·구조 검증
# ─────────────────────────────────────────────
PHASE1_OUTPUT=$(cat "$OUTDIR/phase1_draft.md")

PHASE2_PROMPT="당신은 DevOps 분야 시니어 테크니컬 에디터입니다.
아래 학습 자료 초안을 검토하고, rubric으로 평가한 뒤 수정된 내용을 출력하세요.

[검토 대상 초안]
${PHASE1_OUTPUT}

[검증 Rubric — 각 항목 1~5점 평가 후 JSON으로 먼저 출력]
{
  \"rubric\": {
    \"concept_accuracy\":             { \"score\": 0, \"issues\": [] },
    \"completeness\":                 { \"score\": 0, \"issues\": [] },
    \"logical_flow\":                 { \"score\": 0, \"issues\": [] },
    \"troubleshooting_specificity\":  { \"score\": 0, \"issues\": [] },
    \"source_grounding\":             { \"score\": 0, \"issues\": [] },
    \"readability\":                  { \"score\": 0, \"issues\": [] }
  },
  \"total_score\": 0,
  \"critical_issues\": [],
  \"suggested_additions\": []
}

[출력 순서]
1. 위 JSON rubric을 채워서 출력
2. 수정이 필요한 섹션만 재작성 (통과 섹션은 \"[섹션명]: 검증 통과\" 표기)
3. 추가해야 할 내용은 [추가 제안] 블록으로 명시

[규칙]
- 확실하지 않은 기술적 사실은 수정하지 말고 [확인 필요] 표시
- 코드 정확성 판단은 Phase 3에 위임 (코드는 건드리지 말 것)"

log "Phase 2/4 — Claude: 내용·구조 검증 중..."
# 프롬프트를 임시 파일로 저장 후 stdin으로 주입 (shell 인자 길이 제한 우회)
printf '%s' "$PHASE2_PROMPT" > /tmp/distillio_p2.txt
claude --print "$(cat /tmp/distillio_p2.txt)" > "$OUTDIR/phase2_review.md" 2>/dev/null
log "Phase 2 완료 → $OUTDIR/phase2_review.md"

# ─────────────────────────────────────────────
# Phase 3: Codex — 코드·실습 검증
# ─────────────────────────────────────────────
PHASE2_OUTPUT=$(cat "$OUTDIR/phase2_review.md")

cat > /tmp/distillio_p3.txt << ENDOFPROMPT
당신은 DevOps/SRE 전문 코드 리뷰어입니다.
아래 학습 자료에서 코드 블록과 실습 섹션을 검증하세요.

[검토 대상]
$(cat "$OUTDIR/phase2_review.md")

[코드 검증 항목 — JSON으로 먼저 출력]
{
  "code_blocks": [
    {
      "block_id": 1,
      "language": "",
      "location": "섹션명",
      "checks": {
        "syntax_valid": true,
        "executable": true,
        "prerequisites_listed": true,
        "expected_output_provided": true,
        "security_issues": [],
        "version_specified": true
      },
      "issues": [],
      "fixed_code": ""
    }
  ],
  "overall_hands_on_quality": 0,
  "missing_steps": [],
  "recommended_additions": []
}

[출력 순서]
1. 위 JSON 채워서 출력
2. 수정된 실습 섹션 전체 재작성

[수정 규칙]
- 문법 오류 → fixed_code에 수정본 작성
- 보안 이슈(하드코딩 credentials 등) → critical 표시
- 버전 미명시 → 현재 stable 버전으로 보완
ENDOFPROMPT

log "Phase 3/4 — Codex: 코드·실습 검증 중..."
codex exec "$(cat /tmp/distillio_p3.txt)" > "$OUTDIR/phase3_code_review.md" 2>/dev/null
log "Phase 3 완료 → $OUTDIR/phase3_code_review.md"

# ─────────────────────────────────────────────
# Phase 4: Claude — 최종 머지 (파일 참조 방식으로 토큰 분리)
# ─────────────────────────────────────────────
cat > /tmp/distillio_p4.txt << ENDOFPROMPT
당신은 최종 편집자입니다.
아래 3개 모델의 결과를 머지 전략에 따라 통합하여 완성된 학습 산출물을 출력하세요.

[머지 전략]
우선순위: 사실 오류 수정(Phase 2) > 코드 수정(Phase 3) > 구조 보완 > 원본 유지
충돌 시: 코드는 Phase 3 우선, 내용은 원본 자료에 더 가까운 쪽 채택

[Phase 1 — Gemini 초안]
$(cat "$OUTDIR/phase1_draft.md")

[Phase 2 — Claude 검토]
$(cat "$OUTDIR/phase2_review.md")

[Phase 3 — Codex 코드 검증]
$(cat "$OUTDIR/phase3_code_review.md")

[최종 출력 형식]
---
# ${TOPIC} — 학습 가이드
> 생성일: ${DATE} | 검증: Gemini + Claude + Codex | 대상: ${LEVEL}
---

(6개 섹션 전체 — 각 수정 사항 옆에 [수정: Claude] 또는 [수정: Codex] 태그 표시)

---
## 검증 요약
| 모델 | 역할 | 주요 수정 사항 |
|------|------|--------------|
| Gemini | 초안 생성 | - |
| Claude | 내용·구조 검증 | (rubric 총점 및 주요 이슈) |
| Codex  | 코드·실습 검증 | (발견된 코드 이슈 수) |
---
ENDOFPROMPT

log "Phase 4/4 — Claude: 최종 머지 중..."
claude --print "$(cat /tmp/distillio_p4.txt)" > "$OUTDIR/final_output.md" 2>/dev/null
log "Phase 4 완료 → $OUTDIR/final_output.md"

# 임시 파일 정리
rm -f /tmp/distillio_p2.txt /tmp/distillio_p3.txt /tmp/distillio_p4.txt

# 인덱스 자동 갱신
bash "$(dirname "$0")/index_outputs.sh" > /dev/null 2>&1 || true

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo ""
echo "=============================="
echo " Distillio 파이프라인 완료"
echo "=============================="
echo " 주제   : $TOPIC"
echo " 대상   : $LEVEL"
echo " 날짜   : $DATE"
echo " 경로   : $OUTDIR/"
echo ""
echo " 산출물 목록:"
echo "  - $OUTDIR/phase1_draft.md       (Gemini 초안)"
echo "  - $OUTDIR/phase2_review.md      (Claude 검토)"
echo "  - $OUTDIR/phase3_code_review.md (Codex 코드 검증)"
echo "  - $OUTDIR/final_output.md       (최종 산출물)"
echo ""
echo " 전체 인덱스: output/INDEX.md"
echo "=============================="
