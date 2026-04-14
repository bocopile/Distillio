#!/bin/bash
# Distillio — output/ 인덱스 자동 생성
# 새로운 산출물이 생길 때마다 실행하거나, run_pipeline.sh가 자동 호출합니다.

OUTDIR="output"
INDEX="$OUTDIR/INDEX.md"

mkdir -p "$OUTDIR"

{
  echo "# Distillio — 산출물 인덱스"
  echo "> 마지막 갱신: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "| 주제 | 대상 | 생성일 | 최종 산출물 |"
  echo "|------|------|--------|------------|"

  # output/<topic_slug>/<timestamp>/ 구조 탐색
  for topic_dir in "$OUTDIR"/*/; do
    [ -d "$topic_dir" ] || continue
    topic_slug=$(basename "$topic_dir")

    for run_dir in "$topic_dir"*/; do
      [ -d "$run_dir" ] || continue

      # 메타 파일 읽기
      topic=$(cat "$run_dir/meta_topic.txt"  2>/dev/null || echo "$topic_slug")
      level=$(cat "$run_dir/meta_level.txt"  2>/dev/null || echo "-")
      date_=$(cat "$run_dir/meta_date.txt"   2>/dev/null || echo "-")
      final="$run_dir/final_output.md"

      if [ -f "$final" ]; then
        lines=$(wc -l < "$final")
        echo "| $topic | $level | $date_ | [보기]($final) ($lines lines) |"
      else
        echo "| $topic | $level | $date_ | 생성 중... |"
      fi
    done
  done
} > "$INDEX"

echo "인덱스 갱신 완료 → $INDEX"
cat "$INDEX"
