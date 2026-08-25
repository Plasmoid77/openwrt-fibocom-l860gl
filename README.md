# openwrt-fibocom-l860gl

Установщик модема **Fibocom L860-GL** (Intel XMM7560) на **OpenWrt 25 (apk)**: разворачивает XMM-драйверы, создаёт сетевой интерфейс и ставит панели [4IceG](https://github.com/4IceG) — `3ginfo-lite`, `sms-tool-js`, `modemband` — за один прогон на чистой системе.

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue) ![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green) ![License](https://img.shields.io/badge/license-MIT-lightgrey)

**Русский** · [English](README.en.md) · [中文](README.zh.md)

---

Скрипт устанавливает всё, что нужно для работы и мониторинга модема Fibocom L860-GL на OpenWrt 25, и сам создаёт готовый к работе интерфейс. Второй скрипт — деинсталлятор — начисто откатывает изменения (удобно для тестов без перепрошивки).

### Зачем

L860-GL — это M.2-модем на чипе Intel XMM7560. В отличие от Qualcomm-модемов (qmi/mbim) он работает через протокол **XMM**, а его AT-порт — это `cdc-acm` (`/dev/ttyACM*`), а не `option`/`ttyUSB*`. Чтобы поднять его на OpenWrt и снимать телеметрию, нужен строго определённый набор пакетов и правильная привязка портов/интерфейса. Скрипт всё это разворачивает автоматически и настраивает панели 4IceG под нужный порт, обходя типичные грабли (см. «Известные болячки»).

### Что делает скрипт

1. Спрашивает **APN** (по умолчанию `internet`) и хотите ли ставить **русский язык** для панелей (`[Y/n]`).
2. Подключает модемный фид [132lan](https://openwrt.132lan.ru) и ставит XMM-стек: `luci-proto-xmm`, `xmm-modem`, `kmod-usb-acm`, `kmod-usb-net-cdc-ncm`, `kmod-usb-serial-option` и др., плюс `sms-tool`.
3. Подключает apk-репозиторий [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) и его ключ (идемпотентно, рядом с фидом 132lan).
4. Ставит панели `luci-app-3ginfo-lite`, `luci-app-sms-tool-js`, `luci-app-modemband` (+ русские локали, если выбрано).
5. **Автоопределяет AT-порт**: опрашивает `ttyACM0..3` командой `ATI` и выбирает тот, что отвечает как Fibocom/L860 (с откатом на `/dev/ttyACM0`).
6. Создаёт интерфейс **`LTE_Fibocom_860`** (proto `xmm`, найденный порт, введённый APN, `pdptype`) и добавляет его в firewall-зону `wan`.
7. Настраивает панели под найденный порт: 3ginfo (`device` + `network`), modemband (`set_port` + `iface`), sms-tool (5 портов), и меняет SMS-префикс на `7`.
8. Перезагружает роутер (с 10-секундным отсчётом и возможностью отмены `Ctrl+C`).

### Требования

- OpenWrt **25.x** с пакетным менеджером **apk** (для opkg-сборок скрипт не предназначен).
- Модем **Fibocom L860-GL** (Intel XMM7560), воткнут и определился (порты `/dev/ttyACM*` присутствуют).
- **Интернет на роутере** на момент установки (через другой аплинк или уже поднятый модем) — качаются пакеты и ключи.
- Доступ по **SSH** и права root.

### Установка

Команды выполняются **на роутере** (по SSH):

```
wget -O install-fibocom-l860gl.sh https://raw.githubusercontent.com/lastik9/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

После перезагрузки открой **LuCI → Network → Interfaces** (у `LTE_Fibocom_860` должны появиться Carrier/RX/TX) и **LuCI → Modem(s)** (обнови Ctrl+F5 — сигнал, оператор, бэнд).

Настройки вынесены в переменные в шапке скрипта: имя интерфейса, firewall-зона, APN по умолчанию, тип PDP, PIN, SMS-префикс — при желании правятся в одном месте.

### Удаление

```
wget -O uninstall-fibocom-l860gl.sh https://raw.githubusercontent.com/lastik9/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
sh uninstall-fibocom-l860gl.sh
```

Деинсталлятор снимает интерфейс и его запись из firewall, удаляет пакеты (панели, `luci-proto-xmm`, `sms-tool` и их зависимости), чистит конфиги панелей и добавленные фиды/ключ, затем перезагружается. Безопасен к повторному запуску.

### Известные болячки

- **`add.sh` / `apk update` падает с `Failed to send request: Operation not permitted`, либо панели 4IceG не встали (`error 8` / `unexpected end of file` / `UNTRUSTED signature`)** — виноват **прозрачный прокси** на роутере (Clash / [ssclash](https://github.com/lastik9/openwrt-ssclash) / Mihomo). Фид `openwrt.132lan.ru` он часто заворачивает в REJECT (отсюда `Operation not permitted`), а редирект GitHub рвёт. **Прокси при этом останавливать НЕ нужно** — в режиме «белых списков» это оставит роутер без интернета. Начиная с этой версии скрипт сам находит запущенный Clash/Mihomo и пускает свои загрузки через его локальный прокси `http://127.0.0.1:7890` (env `http_proxy`/`https_proxy`, как в openwrt-ssclash), а ссылки на ключ и фид 4IceG теперь прямые (`raw.githubusercontent.com`, без 302-редиректа). Обычно делать ничего не нужно. Если порт прокси другой — задай его при запуске:

  ```
  CLASH_PROXY=http://127.0.0.1:7890 sh install-fibocom-l860gl.sh
  ```

  Если фид всё равно недоступен — разреши домен в конфиге Mihomo и перезагрузи ядро:

  ```
  rules:
    - DOMAIN-SUFFIX,132lan.ru,DIRECT   # или PROXY в режиме «белых списков»
  ```

  Хвост старого фида (после установки древней версией) чистится так:

  ```
  sed -i '\#4IceG/Modem-extras-apk#d' /etc/apk/repositories.d/customfeeds.list && apk update
  ```

- **`wget` сохранил файл как `index.html`** — за прокси busybox-`wget` теряет имя из URL. Всегда качай с явным именем: `wget -O install-fibocom-l860gl.sh <URL>`.
- **`Failed add repository modem_kmod!`** при работе `add.sh` 132lan — безвредно. Нужные драйверы (`xmm-modem`, `kmod-*`) ставятся из официальных фидов OpenWrt, на установку это не влияет.
- **`Carrier: Absent` после установки** — почти всегда неверный **APN**. Он зависит от оператора: скрипт по умолчанию ставит `internet`, но у части тарифов он другой. Исправь APN в интерфейсе и `Save & Apply`.
- **3ginfo не показывает данные** — проверь AT-порт (`ls -l /dev/ttyACM*`, затем `sms_tool -d /dev/ttyACM0 at ATI`). Если рабочий порт другой — поправь `device` в 3ginfo.
- **Лок бэндов** через modemband или `AT+XACT` — осторожно: если залочить бэнд, которого нет в твоей точке, модем не зарегистрируется. Откат: `AT+XACT=2,,,0` (разрешить все LTE-бэнды). Нумерация LTE-бэндов в `AT+XACT` со сдвигом +100 (B3 → 103, B7 → 107, B20 → 120).
- **Правишь скрипты на Windows?** Сохраняй в переводах строк **LF (Unix)**. CRLF в `#!/bin/sh` ломает запуск на роутере. В репозитории это подстраховано файлом `.gitattributes`.

### Диагностика

```
ls -l /dev/ttyACM*                                   # порты модема
sms_tool -d /dev/ttyACM0 at 'ATI'                    # ответ модема
sms_tool -d /dev/ttyACM0 at 'AT+CSQ'                 # сигнал (xx,yy)
sms_tool -d /dev/ttyACM0 at 'AT+COPS?'               # оператор
sms_tool -d /dev/ttyACM0 at 'AT+CGDCONT?'            # настроенный APN
uci show network.LTE_Fibocom_860                     # конфиг интерфейса
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_Fibocom_860 | grep -i up                # поднят ли интерфейс
logread | grep -i xmm                                # лог протокола XMM
```

### Проверено на

OpenWrt 25.12.x (mediatek/filogic, `aarch64_cortex-a53`), модем Fibocom L860-GL-16, оператор Yota.

### Благодарности

Проект — лишь установщик. Основная работа сделана в проектах **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — панель мониторинга модема
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) — SMS / USSD / AT-команды
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — управление LTE-диапазонами
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk-репозиторий пакетов

Также спасибо [132lan](https://openwrt.132lan.ru) за модемный фид с XMM-драйверами. Приём «обновление за белыми списками» (проксирование трафика роутера через Mihomo) — из проекта [openwrt-ssclash](https://github.com/lastik9/openwrt-ssclash).

Устанавливаемые компоненты — собственность их авторов и распространяются под их лицензиями. Лицензия MIT покрывает только код этого установщика.

### Лицензия

[MIT](LICENSE) © 2026 lastik9
