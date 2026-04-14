# Distillio — Multi-LLM Cross-Validation Prompt Specification

> 이 파일은 Claude, Gemini, Codex CLI를 직접 호출하여 교차검증을 수행하는
> 파이프라인 명세서입니다. 각 Phase의 프롬프트를 그대로 CLI에 주입합니다.

---

## 모델 역할 분담

| 모델 | CLI 명령어 | 담당 역할 | 이유 |
|------|-----------|----------|------|
| **Gemini** | `gemini --prompt` | Phase 1: 초안 생성 (Generator) | 대용량 컨텍스트(1M 토큰) 처리에 강점 |
| **Claude** | `claude --print` | Phase 2: 내용·구조 검증 (Critic) | 논리적 추론, 사실 오류 탐지에 강점 |
| **Codex** | `codex exec` | Phase 3: 코드·실습 검증 (Code Verifier) | 코드 정확성, 실행 가능성 검증에 강점 |

---

## 공통 컨텍스트 변수

파이프라인 실행 전 아래 변수를 환경에 세팅하세요.

```bash
export TOPIC="Kubernetes Operator 개발"          # 주제
export LEVEL="DevOps 엔지니어 (3년 이상)"         # 대상 수준
export SOURCE="https://..."                       # 원본 자료 URL or 파일 경로
export WEEK="3"                                   # 주차 (커리큘럼 모드일 때)
export OUTPUT_FORMAT="markdown"                   # markdown | html
```

---

## Phase 1: 초안 생성 (Gemini — Generator)

**목적**: 원본 자료를 읽고 학습 산출물 초안을 생성합니다.

### 프롬프트

```
당신은 DevOps/AIOps 전문 교육 콘텐츠 작성자입니다.

[입력 정보]
- 주제: {{TOPIC}}
- 대상: {{LEVEL}}
- 원본 자료: {{SOURCE}}
- 출력 형식: {{OUTPUT_FORMAT}}

[필수 출력 구조 — 반드시 이 순서와 헤더를 지켜야 합니다]

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
- 단계별 실행 코드 (복사-붙여넣기 가능해야 함)
- 예상 결과 화면

## 6. 참고 자료 (References)
- 공식 문서 링크
- 관련 논문 또는 블로그 (최신 우선)

[출력 규칙]
- 각 섹션 시작 전 해당 섹션의 핵심 요약을 1문장으로 적을 것
- 코드 블록은 반드시 언어 명시 (```bash, ```yaml, ```python)
- 실제 운영에서 검증된 값만 사용, 추정값에는 [추정] 표시
- 원본 자료에 없는 내용 추가 시 [보강] 표시
```

### CLI 호출

```bash
gemini --prompt "
주제: $TOPIC
대상: $LEVEL
원본: $SOURCE

$(cat PROMPT.md | sed -n '/## Phase 1/,/## Phase 2/p' | grep -A999 '### 프롬프트' | tail -n +3 | head -n -1)
" > output/phase1_draft.md
```

---

## Phase 2: 내용·구조 검증 (Claude — Critic)

**목적**: Phase 1 초안의 논리적 오류, 누락, 구조 문제를 검증하고 수정안을 제시합니다.

### 프롬프트

```
당신은 DevOps 분야 시니어 테크니컬 에디터입니다.
아래 학습 자료 초안을 검토하고, 정해진 rubric으로 평가한 뒤 수정된 최종본을 출력하세요.

[검토 대상 초안]
{{PHASE1_OUTPUT}}

[검증 Rubric — 각 항목을 1~5점으로 평가]

```json
{
  "rubric": {
    "concept_accuracy": {
      "score": 0,
      "issues": [],
      "description": "개념 정의의 사실적 정확성"
    },
    "completeness": {
      "score": 0,
      "issues": [],
      "description": "6개 필수 섹션 모두 존재 여부"
    },
    "logical_flow": {
      "score": 0,
      "issues": [],
      "description": "개념 → 활용 → 운영 → 트러블슈팅 순서의 논리성"
    },
    "troubleshooting_specificity": {
      "score": 0,
      "issues": [],
      "description": "트러블슈팅이 실제 에러 메시지와 해결책을 포함하는지"
    },
    "source_grounding": {
      "score": 0,
      "issues": [],
      "description": "내용이 원본 자료에 근거하는지, 환각은 없는지"
    },
    "readability": {
      "score": 0,
      "issues": [],
      "description": "대상 독자 수준에 맞는 설명인지"
    }
  },
  "total_score": 0,
  "critical_issues": [],
  "suggested_additions": []
}
```

[출력 형식]
1. 위 JSON rubric을 채워서 먼저 출력
2. 수정이 필요한 섹션만 재작성 (수정 없는 섹션은 "[섹션명]: 검증 통과" 로 표기)
3. 추가해야 할 내용이 있으면 [추가 제안] 블록으로 명시

[규칙]
- 원본 자료에 없는 내용을 새로 만들지 말 것
- 확실하지 않은 기술적 사실은 수정하지 말고 [확인 필요] 표시
- 코드는 직접 실행하지 않으므로 코드 정확성 판단은 Phase 3에 위임
```

### CLI 호출

```bash
PHASE1_OUTPUT=$(cat output/phase1_draft.md)

claude --print "
[검토 대상 초안]
$PHASE1_OUTPUT

$(cat PROMPT.md | sed -n '/## Phase 2/,/## Phase 3/p' | grep -A999 '### 프롬프트' | tail -n +3 | head -n -1)
" > output/phase2_review.md
```

---

## Phase 3: 코드·실습 검증 (Codex — Code Verifier)

**목적**: 실습 섹션의 코드 정확성, 실행 가능성, 보안 이슈를 검증합니다.

### 프롬프트

```
당신은 DevOps/SRE 전문 코드 리뷰어입니다.
아래 학습 자료에서 코드 블록과 실습 섹션만 추출하여 검증하세요.

[검토 대상]
{{PHASE2_OUTPUT}}

[코드 검증 체크리스트]

각 코드 블록에 대해 아래를 확인하세요:

```json
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
```

[수정 규칙]
- 문법 오류가 있으면 반드시 수정된 코드를 fixed_code에 작성
- 보안 이슈(하드코딩된 credentials, --privileged 남용 등)는 critical로 표시
- 버전이 명시되지 않은 패키지/툴은 현재 stable 버전으로 보완
- 실행 순서가 바뀌면 안 되는 경우 "순서 의존성" 명시

[출력 형식]
1. 위 JSON 먼저 출력
2. 수정된 실습 섹션 전체를 재작성하여 출력
```

### CLI 호출

```bash
PHASE2_OUTPUT=$(cat output/phase2_review.md)

codex exec "
[검토 대상]
$PHASE2_OUTPUT

$(cat PROMPT.md | sed -n '/## Phase 3/,/## Phase 4/p' | grep -A999 '### 프롬프트' | tail -n +3 | head -n -1)
" > output/phase3_code_review.md
```

---

## Phase 4: 최종 머지 (Claude — Final Editor)

**목적**: 3개 모델의 결과를 통합하여 최종 산출물을 생성합니다.

### 머지 전략

```
우선순위 규칙:
1. 사실 오류 수정 (Phase 2 Claude) — 최우선 적용
2. 코드 수정 (Phase 3 Codex) — 실습 섹션에 적용
3. 구조 보완 (Phase 2 suggested_additions) — 가능한 경우 적용
4. 원본 초안 (Phase 1 Gemini) — 위 수정사항 외 유지

충돌 해결 규칙:
- Phase 2와 Phase 3이 충돌하면 Phase 3 우선 (코드는 Codex가 권위자)
- 내용 충돌은 원본 자료에 더 가까운 쪽 채택
- 판단 불가 시 [검토 필요] 태그 부착
```

### 프롬프트

```
당신은 최종 편집자입니다. 아래 3개 결과물을 머지 전략에 따라 통합하여
완성된 학습 산출물을 출력하세요.

[Phase 1 — Gemini 초안]
{{PHASE1_OUTPUT}}

[Phase 2 — Claude 검토]
{{PHASE2_OUTPUT}}

[Phase 3 — Codex 코드 검증]
{{PHASE3_OUTPUT}}

[머지 전략]
- 사실 오류 수정 최우선 적용
- 코드는 Phase 3 수정본 사용
- 원본 구조(6개 섹션) 반드시 유지
- 각 수정 사항 옆에 [수정: Claude] [수정: Codex] 태그 표시

[최종 출력 형식]
# {{TOPIC}} — 학습 가이드
> 생성일: {{DATE}} | 검증: Claude + Gemini + Codex | 대상: {{LEVEL}}

(이후 6개 섹션 전체)

---
## 검증 요약
| 모델 | 총점 | 주요 수정 사항 |
|------|------|--------------|
| Gemini (Generator) | - | 초안 생성 |
| Claude (Critic) | {{RUBRIC_SCORE}}/30 | {{MAIN_ISSUES}} |
| Codex (Code Verifier) | {{CODE_SCORE}}/N | {{CODE_ISSUES}} |
```

### CLI 호출

```bash
PHASE1_OUTPUT=$(cat output/phase1_draft.md)
PHASE2_OUTPUT=$(cat output/phase2_review.md)
PHASE3_OUTPUT=$(cat output/phase3_code_review.md)
DATE=$(date '+%Y-%m-%d')

claude --print "
[Phase 1 — Gemini 초안]
$PHASE1_OUTPUT

[Phase 2 — Claude 검토]
$PHASE2_OUTPUT

[Phase 3 — Codex 코드 검증]
$PHASE3_OUTPUT

주제: $TOPIC | 대상: $LEVEL | 날짜: $DATE

$(cat PROMPT.md | sed -n '/## Phase 4/,/---/p' | grep -A999 '### 프롬프트' | tail -n +3 | head -n -3)
" > output/final_output.md

echo "완료: output/final_output.md"
```

---

## 전체 파이프라인 실행 스크립트

```bash
#!/bin/bash
# run_pipeline.sh — Distillio Multi-LLM Pipeline

set -e

# 변수 설정
TOPIC="${1:-Kubernetes Operator}"
LEVEL="${2:-DevOps 엔지니어 (3년 이상)}"
SOURCE="${3:-}"
DATE=$(date '+%Y-%m-%d')

mkdir -p output

echo "[1/4] Gemini — 초안 생성 중..."
gemini --prompt "주제: $TOPIC, 대상: $LEVEL, 원본: $SOURCE
$(grep -A100 'Phase 1: 초안 생성' PROMPT.md | grep -A50 '### 프롬프트' | sed '1d;/^###/q' | head -n -1)
" > output/phase1_draft.md

echo "[2/4] Claude — 내용 검증 중..."
claude --print "$(cat output/phase1_draft.md)
$(grep -A100 'Phase 2: 내용' PROMPT.md | grep -A50 '### 프롬프트' | sed '1d;/^###/q' | head -n -1)
" > output/phase2_review.md

echo "[3/4] Codex — 코드 검증 중..."
codex exec "$(cat output/phase2_review.md)
$(grep -A100 'Phase 3: 코드' PROMPT.md | grep -A50 '### 프롬프트' | sed '1d;/^###/q' | head -n -1)
" > output/phase3_code_review.md

echo "[4/4] Claude — 최종 머지 중..."
claude --print "
[Phase 1 Gemini]: $(cat output/phase1_draft.md)
[Phase 2 Claude]: $(cat output/phase2_review.md)
[Phase 3 Codex]: $(cat output/phase3_code_review.md)
주제: $TOPIC | 대상: $LEVEL | 날짜: $DATE
$(grep -A100 'Phase 4: 최종' PROMPT.md | grep -A50 '### 프롬프트' | sed '1d;/^###/q' | head -n -1)
" > output/final_output.md

echo ""
echo "파이프라인 완료."
echo "최종 산출물: output/final_output.md"
```

### 사용법

```bash
chmod +x run_pipeline.sh

# 기본 실행
./run_pipeline.sh "Kubernetes Operator" "DevOps 엔지니어" "https://..."

# URL 없이 주제만으로 실행 (모델이 자체 지식 사용)
./run_pipeline.sh "ArgoCD GitOps 패턴"
```

---

## 커리큘럼 모드 (긴 자료)

원본 자료가 방대한 경우 먼저 커리큘럼을 생성한 뒤 주차별로 위 파이프라인을 반복합니다.

```bash
# Step 0: 커리큘럼 생성 (Gemini — 대용량 컨텍스트)
gemini --prompt "
아래 자료를 분석하여 $LEVEL 대상의 학습 커리큘럼을 설계하세요.

[원본 자료]
$SOURCE

[출력 형식]
총 주차: N주
각 주차별:
- Week N: 주제
  - 핵심 키워드 3개
  - 예상 소요 시간
  - 이전 주차와의 연결성
" > output/curriculum.md

# Step 1~N: 주차별 산출물 생성
TOTAL_WEEKS=$(grep -c "^- Week" output/curriculum.md)
for week in $(seq 1 $TOTAL_WEEKS); do
  echo "Week $week 생성 중..."
  WEEK=$week ./run_pipeline.sh "$TOPIC" "$LEVEL" "$SOURCE"
  mv output/final_output.md output/week${week}_output.md
done
```

---

## 출력 디렉토리 구조

```
output/
├── curriculum.md          # 커리큘럼 (커리큘럼 모드)
├── phase1_draft.md        # Gemini 초안
├── phase2_review.md       # Claude 검토
├── phase3_code_review.md  # Codex 코드 검증
├── final_output.md        # 최종 산출물
└── week{N}_output.md      # 주차별 산출물 (커리큘럼 모드)
```
