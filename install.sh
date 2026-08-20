echo
echo "============================================================"
echo "       INSTALAÇÃO AUTOMÁTICA MOBOX + TERMUX + XFCE"
echo "============================================================"
echo

# ============================================================
# 1. BAIXAR E EXTRAIR MOBOX
# ============================================================

echo "===== 1. BAIXANDO MOBOX ====="

MOBOX_URL="https://github.com/jaycore/mobox-patched/releases/download/Mobox_Patched_3.0/mobox_patched_3.0.tar.gz"
MOBOX_FILE="/sdcard/Download/mobox_patched_3.0.tar.gz"

curl -L "$MOBOX_URL" -o "$MOBOX_FILE"

echo
echo "Download concluído."
echo

echo "===== 2. EXTRAINDO MOBOX ====="

tar -zxf "$MOBOX_FILE" \
    -C /data/data/com.termux/files

echo
echo "Mobox extraído."
echo

# ============================================================
# 2. STORAGE
# ============================================================

echo "===== 2. CONFIGURANDO STORAGE ====="

termux-setup-storage

echo
echo "IMPORTANTE: se o Android mostrar a solicitação de acesso,"
echo "conceda a permissão e pressione ENTER."
read -r

# ============================================================
# 3. TESTAR MIRRORS
# ============================================================

echo
echo "===== 3. TESTE DE MIRRORS DO TERMUX ====="
echo

pkg update -y && pkg install -y curl termux-tools

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ============================================================
# OBTER MIRRORS DA PRÓPRIA LISTA DO TERMUX
# ============================================================

MIRROR_DIR="$PREFIX/etc/termux/mirrors"

if [ ! -d "$MIRROR_DIR" ]; then
    echo "ERRO: lista de mirrors do Termux não encontrada:"
    echo "$MIRROR_DIR"
    exit 1
fi

MIRRORS=$(
    find "$MIRROR_DIR" -type f -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
        cat "$file"
    done |
    sed 's/[[:space:]]*#.*//' |
    sed '/^[[:space:]]*$/d' |
    sed 's:/*$::' |
    sort -u
)

if [ -z "$MIRRORS" ]; then
    echo "ERRO: nenhum mirror encontrado na instalação do Termux."
    exit 1
fi

echo "Mirrors encontrados na instalação do Termux:"
echo "$MIRRORS"
echo

TESTFILE="dists/stable/Release"
RESULTS="$TMP/results"

printf "%-5s %-45s %-12s %-12s\n" \
    "#" "MIRROR" "TEMPO(s)" "KB/s"

printf "%-5s %-45s %-12s %-12s\n" \
    "---" "---------------------------------------------" \
    "----------" "----------"

N=0

while IFS= read -r mirror; do

    [ -z "$mirror" ] && continue

    N=$((N + 1))

    url="$mirror/$TESTFILE"
    out="$TMP/test-$N"

    printf "[%02d] Testando %s ...\n" "$N" "$mirror"

    result=$(
        curl -L -sS \
            -o "$out" \
            -w "%{time_total} %{speed_download}" \
            --connect-timeout 4 \
            --max-time 12 \
            "$url" 2>/dev/null || true
    )

    time=$(printf "%s" "$result" | awk '{print $1}')
    speed=$(printf "%s" "$result" | awk '{print $2}')

    if [ -n "$time" ] &&
       [ -n "$speed" ] &&
       [ "$speed" != "0" ] &&
       [ -s "$out" ]; then

        kb=$(awk "BEGIN {printf \"%.1f\", $speed/1024}")

        printf "%s|%s|%s\n" \
            "$kb" "$time" "$mirror" >> "$RESULTS"

    else

        printf "0|999|%s\n" "$mirror" >> "$RESULTS"

    fi

done <<EOF
$MIRRORS
EOF

echo
echo "===== RANKING ====="

sort -t"|" -k1,1nr "$RESULTS" |
awk -F"|" '
{
    n++

    if ($1 == 0)
        printf "%-5s %-45s INDISPONIVEL\n", n, $3
    else
        printf "%-5s %-45s %-12s %-12s\n",
               n, $3, $2, $1
}'

BEST=$(
    sort -t"|" -k1,1nr "$RESULTS" |
    awk -F"|" '$1 > 0 {print $3; exit}'
)

if [ -z "$BEST" ]; then
    echo
    echo "ERRO: nenhum mirror respondeu."
    exit 1
fi

echo
echo "===== MIRROR MAIS RÁPIDO ====="
echo "$BEST"
echo

echo "Configurando o Termux..."

mkdir -p "$PREFIX/etc/apt/sources.list.d"

printf "deb %s stable main\n" "$BEST" \
    > "$PREFIX/etc/apt/sources.list"

echo
echo "===== CONFIGURAÇÃO ====="
cat "$PREFIX/etc/apt/sources.list"

# ============================================================
# 4. UPDATE / UPGRADE
# ============================================================

echo
echo "===== 4. ATUALIZANDO TERMUX ====="

pkg update
pkg upgrade -y

# ============================================================
# 5. REPOSITÓRIOS
# ============================================================

echo
echo "===== 5. HABILITANDO REPOSITÓRIOS ====="

pkg install -y x11-repo
pkg install -y tur-repo

pkg update

# ============================================================
# 6. PACOTES TERMUX
# ============================================================

echo
echo "===== 6. INSTALANDO PACOTES ====="

pkg install -y \
    x11-repo \
    termux-x11-nightly \
    xfce4 \
    dbus \
    pulseaudio \
    proot \
    proot-distro \
    curl \
    wget \
    tar

# ============================================================
# 7. COMANDO "start"
# ============================================================

echo
echo "===== 7. CRIANDO COMANDO start ====="

cat > "$PREFIX/bin/start" <<'START_EOF'
#!/data/data/com.termux/files/usr/bin/sh

# ==========================================================
# XFCE4 NATIVO DO TERMUX
# ==========================================================

export DISPLAY=:0

# Inicia Termux:X11 caso ainda não esteja rodando
if ! pgrep -f "termux-x11" >/dev/null 2>&1; then
    termux-x11 :0 >/dev/null 2>&1 &
    sleep 2
fi

# Abre automaticamente a interface do Termux:X11
am start --user 0 \
    -n com.termux.x11/com.termux.x11.MainActivity \
    >/dev/null 2>&1 || true

sleep 1

# Inicia XFCE do Termux
exec startxfce4
START_EOF

chmod +x "$PREFIX/bin/start"

# ============================================================
# 8. COMANDO "start-proot"
# ============================================================

echo
echo "===== 8. CRIANDO COMANDO start-proot ====="

cat > "$PREFIX/bin/start-proot" <<'PROOT_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# ==========================================================
# UBUNTU PROOT-DISTRO + XFCE4 + TERMUX:X11
# Usuário: inaciopestana
# ==========================================================

set -e

export DISPLAY=:0

# ----------------------------------------------------------
# Inicia Termux:X11
# ----------------------------------------------------------

if ! pgrep -f "termux-x11" >/dev/null 2>&1; then
    termux-x11 :0 >/dev/null 2>&1 &
    sleep 2
fi

# ----------------------------------------------------------
# Abre automaticamente a janela do Termux:X11
# ----------------------------------------------------------

am start --user 0 \
    -n com.termux.x11/com.termux.x11.MainActivity \
    >/dev/null 2>&1 || true

sleep 1

# ----------------------------------------------------------
# Entra no Ubuntu
# ----------------------------------------------------------

exec proot-distro login ubuntu \
    --shared-tmp \
    --user inaciopestana \
    -- bash -c '

        # ==================================================
        # AMBIENTE DO USUÁRIO
        # ==================================================

        export HOME=/home/inaciopestana
        export USER=inaciopestana
        export LOGNAME=inaciopestana

        export DISPLAY=:0
        export PULSE_SERVER=127.0.0.1

        export XDG_RUNTIME_DIR=/tmp/runtime-inaciopestana

        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"

        # ==================================================
        # IMPORTANTE
        #
        # Usar somente executáveis do Ubuntu.
        # Não deixar o PATH do Termux contaminar o XFCE.
        # ==================================================

        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

        unset PREFIX
        unset LD_PRELOAD
        unset LD_LIBRARY_PATH

        # ==================================================
        # XFCE DO UBUNTU
        # ==================================================

        exec /usr/bin/startxfce4
    '
PROOT_EOF

chmod +x "$PREFIX/bin/start-proot"

echo "============================================================"
echo " TERMUX NATIVO - MESA + TURNIP + ZINK"
echo "============================================================"
echo

echo "[1/7] Atualizando repositórios..."
pkg update -y

echo
echo "[2/7] Instalando Mesa / Turnip / Vulkan / Zink / glmark2..."
pkg install -y \
    mesa \
    mesa-vulkan-icd-freedreno \
    vulkan-loader \
    vulkan-tools \
    glmark2

echo
echo "[3/7] Conferindo versões instaladas..."
echo
dpkg-query -W \
    -f="\${Package}\t\${Version}\n" \
    mesa \
    mesa-vulkan-icd-freedreno \
    vulkan-loader \
    glmark2 \
    2>/dev/null || true

echo
echo "[4/7] Conferindo bibliotecas Turnip/Freedreno..."
echo

find "$PREFIX" \
    -type f \
    \( -iname "*turnip*" -o -iname "*freedreno*" \) \
    2>/dev/null \
    | sort

echo
echo "[5/7] Conferindo ICD Vulkan..."
echo

find "$PREFIX" \
    -type f \
    \( -name "*.json" -o -name "*icd*" \) \
    2>/dev/null \
    | grep -Ei "vulkan|freedreno|turnip|mesa" \
    | sort || true

echo
echo "[6/7] Testando Vulkan..."
echo

if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary 2>&1 | head -100 || true
else
    echo "vulkaninfo não encontrado."
fi

echo
echo "============================================================"
echo " TESTE OPENGL / ZINK / TURNIP"
echo "============================================================"
echo

glmark2 2>&1

echo
echo "============================================================"
echo " RESULTADO"
echo "============================================================"
echo
echo "O resultado esperado é semelhante a:"
echo
echo "GL_VENDOR:      Mesa"
echo "GL_RENDERER:    zink Vulkan 1.4(Turnip Adreno (TM) 740 (MESA_TURNIP))"
echo "GL_VERSION:     4.6 ... Mesa 26.0.6"
echo


# ============================================================
# 10. VERIFICAÇÃO
# ============================================================

echo
echo "============================================================"
echo "                  INSTALAÇÃO CONCLUÍDA"
echo "============================================================"
echo

echo "Comandos criados:"
echo
echo "  start"
echo "      -> XFCE nativo do Termux"
echo
echo "  start-proot"
echo "      -> Ubuntu proot-distro + XFCE do Ubuntu"
echo

echo "Verificando:"
echo

command -v start
command -v start-proot

echo
echo "============================================================"
echo " ATENÇÃO: O aplicativo Termux:X11 precisa estar instalado"
echo " no Android para os comandos gráficos funcionarem."
echo "============================================================"
echo
