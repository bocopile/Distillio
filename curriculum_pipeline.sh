#!/bin/bash
# Distillio — Curriculum Mode (긴 자료용)
# 원본 자료가 방대할 때: 커리큘럼 생성 → 주차별 파이프라인 실행
# Usage: ./curriculum_pipeline.sh "주제" "대상 수준" "원본 URL or 파일경로"

set -e

TOPIC="${1:-Kubernetes 완전정복}"
LEVEL="${2:-DevOps 엔지니어 (3년 이상)}"
SOURCE="${3:-}"
DATE=$(date '+%Y-%m-%d')
OUTDIR="output/curriculum_$(date '+%Y%m%d_%H%M%S')"

mkdir -p "$OUTDIR"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

command -v gemini &>/dev/null || die "gemini CLI가 없습니다."
command -v claude  &>/dev/null || die "claude CLI가 없습니다."

# ─────────────────────────────────────────────
# Step 0: 커리큘럼 생성 (Gemini)
# ─────────────────────────────────────────────
log "Step 0 — Gemini: 커리큘럼 설계 중..."

CURRICULUM_PROMPT="당신은 DevOps/AIOps 전문 교육 과정 설계자입니다.
아래 자료를 분석하여 체계적인 학습 커리큘럼을 설계하세요.

[입력 정보]
- 주제: ${TOPIC}
- 대상: ${LEVEL}
- 원본 자료: ${SOURCE:-없음 (자체 지식 활용)}

[출력 형식 — 반드시 아래 형식 준수]
총 주차: N주

Week 1: 주제명
  - 키워드: 키워드1, 키워드2, 키워드3
  - 학습 목표: 한 문장
  - 이전 주차 연결: (1주차는 '없음')

Week 2: 주제명
  - 키워드: ...
  ...

[설계 원칙]
- 기초 → 심화 → 운영 → 트러블슈팅 순서
- 각 주차는 독립적으로도 학습 가능한 단위로 구성
- 실습 가능한 주제 위주로 구성"

gemini --prompt "$CURRICULUM_PROMPT" > "$OUTDIR/curriculum.md" 2>/dev/null
log "커리큘럼 생성 완료 → $OUTDIR/curriculum.md"

# ─────────────────────────────────────────────
# Step 0-1: 주차 수 파싱
# ─────────────────────────────────────────────
TOTAL_WEEKS=$(grep -c "^Week " "$OUTDIR/curriculum.md" 2>/dev/null || echo 0)

if [ "$TOTAL_WEEKS" -eq 0 ]; then
  log "경고: 주차를 파싱하지 못했습니다. curriculum.md를 직접 확인하세요."
  TOTAL_WEEKS=1
fi

log "총 ${TOTAL_WEEKS}주 커리큘럼 확인됨"
echo ""
cat "$OUTDIR/curriculum.md"
echo ""

# ─────────────────────────────────────────────
# Step 1~N: 주차별 파이프라인 실행
# ─────────────────────────────────────────────
for week in $(seq 1 "$TOTAL_WEEKS"); do
  WEEK_TOPIC=$(grep "^Week ${week}:" "$OUTDIR/curriculum.md" | sed "s/^Week ${week}: //")
  WEEK_OUTDIR="$OUTDIR/week${week}"
  mkdir -p "$WEEK_OUTDIR"

  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "Week ${week}/${TOTAL_WEEKS}: ${WEEK_TOPIC}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # run_pipeline.sh를 주차별로 호출
  OUTDIR="$WEEK_OUTDIR" bash run_pipeline.sh "$WEEK_TOPIC" "$LEVEL" "$SOURCE" 2>/dev/null

  log "Week ${week} 완료 → $WEEK_OUTDIR/final_output.md"
  echo ""
done

# ─────────────────────────────────────────────
# 전체 목차 생성
# ─────────────────────────────────────────────
log "목차(index.md) 생성 중..."

{
  echo "# ${TOPIC} — 전체 커리큘럼"
  echo "> 생성일: ${DATE} | 검증: Gemini + Claude + Codex | 대상: ${LEVEL}"
  echo ""
  echo "## 주차별 목차"
  echo ""
  for week in $(seq 1 "$TOTAL_WEEKS"); do
    WEEK_TOPIC=$(grep "^Week ${week}:" "$OUTDIR/curriculum.md" | sed "s/^Week ${week}: //")
    echo "- [Week ${week}: ${WEEK_TOPIC}](week${week}/final_output.md)"
  done
} > "$OUTDIR/index.md"

echo ""
echo "=============================="
echo " Distillio 커리큘럼 완료"
echo "=============================="
echo " 주제   : $TOPIC"
echo " 총 주차 : ${TOTAL_WEEKS}주"
echo " 출력   : $OUTDIR/"
echo ""
echo " 파일 목록:"
echo "  - $OUTDIR/curriculum.md   (전체 커리큘럼)"
echo "  - $OUTDIR/index.md        (주차별 목차)"
for week in $(seq 1 "$TOTAL_WEEKS"); do
  echo "  - $OUTDIR/week${week}/final_output.md"
done
echo "=============================="
