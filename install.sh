#!/bin/bash
# 安装 web-evaluate skill 到 Claude Code skills 目录

set -e

SKILL_NAME="web-evaluate"
SKILLS_DIR="$HOME/.claude/skills"
TARGET_DIR="$SKILLS_DIR/$SKILL_NAME"

echo "Installing $SKILL_NAME skill..."

# 创建目标目录
mkdir -p "$TARGET_DIR"

# 复制 SKILL.md
cp "$(dirname "$0")/SKILL.md" "$TARGET_DIR/SKILL.md"

echo "✓ Installed to: $TARGET_DIR"
echo ""
echo "Usage in Claude Code:"
echo "  /web-evaluate"
echo ""
echo "Or type: '帮我评估页面性能' / 'web performance audit'"
