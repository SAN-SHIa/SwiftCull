#!/bin/bash
# SwiftCull 快捷启动脚本
# 用法: ./run.sh [command]
#
# 命令:
#   run       构建并启动应用 (默认)
#   build     仅构建 Debug 版本
#   release   构建 Release 版本
#   clean     清理构建产物
#   dmg       构建并打包 DMG
#   open      在 Xcode 中打开项目
#   gen       重新生成 .xcodeproj
#   help      显示帮助信息

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="SwiftCull"
SCHEME="SwiftCull"
BUNDLE_ID="com.swiftcull.app"
BUILD_DIR="${PROJECT_DIR}/build"
APP_DEBUG="${BUILD_DIR}/Debug/${PROJECT_NAME}.app"
APP_RELEASE="${BUILD_DIR}/Release/${PROJECT_NAME}.app"

# ── 颜色 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}==>${NC} $*"; }
ok()    { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}==>${NC} $*"; }
err()   { echo -e "${RED}==>${NC} $*"; }

# ── 预检 ──────────────────────────────────────────────
check_prerequisites() {
    if ! command -v xcodebuild &>/dev/null; then
        err "未找到 xcodebuild，请先安装 Xcode"
        exit 1
    fi
    if [ ! -d "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" ]; then
        err "未找到 ${PROJECT_NAME}.xcodeproj"
        if command -v xcodegen &>/dev/null; then
            warn "检测到 xcodegen，尝试自动生成..."
            (cd "${PROJECT_DIR}" && xcodegen generate)
        else
            err "请先运行 xcodegen generate 或安装 xcodegen: brew install xcodegen"
            exit 1
        fi
    fi
}

# ── 构建 ──────────────────────────────────────────────
do_build() {
    local config="${1:-Debug}"
    local app_path="${BUILD_DIR}/${config}/${PROJECT_NAME}.app"

    info "构建 ${PROJECT_NAME} (${config})..."
    xcodebuild \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration "${config}" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        CONFIGURATION_BUILD_DIR="${BUILD_DIR}/${config}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE=Automatic \
        build \
        | tail -3

    if [ ! -d "${app_path}" ]; then
        err "构建失败: ${app_path} 不存在"
        exit 1
    fi

    ok "构建成功: ${app_path}"
    ok "应用大小: $(du -sh "${app_path}" | cut -f1)"
}

# ── 运行 ──────────────────────────────────────────────
do_run() {
    do_build Debug
    info "启动 ${PROJECT_NAME}..."
    open "${APP_DEBUG}"
    ok "${PROJECT_NAME} 已启动"
}

# ── Release ───────────────────────────────────────────
do_release() {
    do_build Release
}

# ── 清理 ──────────────────────────────────────────────
do_clean() {
    info "清理构建产物..."
    rm -rf "${BUILD_DIR}"
    ok "清理完成"
}

# ── DMG ───────────────────────────────────────────────
do_dmg() {
    local dmg_script="${PROJECT_DIR}/build_dmg.sh"
    if [ ! -f "${dmg_script}" ]; then
        err "未找到 build_dmg.sh"
        exit 1
    fi
    info "打包 DMG..."
    bash "${dmg_script}"
}

# ── 打开 Xcode ────────────────────────────────────────
do_open() {
    local xcodeproj="${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj"
    if [ ! -d "${xcodeproj}" ]; then
        err "未找到 ${PROJECT_NAME}.xcodeproj"
        exit 1
    fi
    info "在 Xcode 中打开项目..."
    open "${xcodeproj}"
}

# ── 生成项目 ──────────────────────────────────────────
do_gen() {
    if ! command -v xcodegen &>/dev/null; then
        err "未找到 xcodegen，请先安装: brew install xcodegen"
        exit 1
    fi
    info "重新生成 .xcodeproj..."
    (cd "${PROJECT_DIR}" && xcodegen generate)
    ok "项目文件已更新"
}

# ── 帮助 ──────────────────────────────────────────────
do_help() {
    echo ""
    echo -e "${BOLD}SwiftCull 快捷启动脚本${NC}"
    echo ""
    echo "用法: ./run.sh [command]"
    echo ""
    echo "命令:"
    echo -e "  ${GREEN}run${NC}       构建并启动应用 (默认)"
    echo -e "  ${GREEN}build${NC}     仅构建 Debug 版本"
    echo -e "  ${GREEN}release${NC}   构建 Release 版本"
    echo -e "  ${GREEN}clean${NC}     清理构建产物"
    echo -e "  ${GREEN}dmg${NC}       构建并打包 DMG 安装包"
    echo -e "  ${GREEN}open${NC}      在 Xcode 中打开项目"
    echo -e "  ${GREEN}gen${NC}       用 xcodegen 重新生成 .xcodeproj"
    echo -e "  ${GREEN}help${NC}      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  ./run.sh          # 构建并启动"
    echo "  ./run.sh build    # 仅构建"
    echo "  ./run.sh clean    # 清理后重新构建"
    echo "  ./run.sh dmg      # 打包发布用 DMG"
    echo ""
}

# ── 主入口 ─────────────────────────────────────────────
main() {
    local cmd="${1:-run}"

    case "${cmd}" in
        run)     check_prerequisites; do_run ;;
        build)   check_prerequisites; do_build Debug ;;
        release) check_prerequisites; do_release ;;
        clean)   do_clean ;;
        dmg)     check_prerequisites; do_dmg ;;
        open)    do_open ;;
        gen)     do_gen ;;
        help|-h|--help) do_help ;;
        *)
            err "未知命令: ${cmd}"
            do_help
            exit 1
            ;;
    esac
}

main "$@"
