# VideoControls+

<p align="center">
  <img src="assets/showcase.png" width="760" alt="VideoControls+ Showcase"><br><br>
  <b>Современная перемотка и регулировка скорости для плеера iOS 6.0 – 6.1.6</b><br>
  <i>Пиксель-перфектные скевоморфные кнопки перемотки на 10 секунд и горизонтальный HUD выбора скорости для старых версий iOS.</i>
</p>

<p align="center">
  <a href="https://noname122021.github.io/cydia-repo/#videocontrolsplus"><img src="https://img.shields.io/badge/Cydia%20Repo-Репозиторий-orange.svg?style=for-the-badge" alt="Cydia Repo"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-6.0%20--%206.1.6-blue.svg" alt="iOS 4.3 - 6.1.6">
  <img src="https://img.shields.io/badge/arch-ARMv7%20(32--bit)-success.svg" alt="ARMv7 32-bit">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="License">
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> • <a href="README.ru.md"><b>Русский</b></a>
</p>

> ### 📦 **[Открыть VideoControls+ в Cydia-репозитории](https://noname122021.github.io/cydia-repo/)**
> - **Установка репозитория в один клик:** [Добавить источник в Cydia (`cydia://`)](cydia://url/https://cydia.saurik.com/api/share#?source=https://noname122021.github.io/cydia-repo/)
> - **APT URL источника:** `https://noname122021.github.io/cydia-repo/`

---

## Обзор

**VideoControls+** обновляет стандартный системный видеоплеер (`MediaPlayer.framework`), работающий в Safari, Classic YouTube, приложении «Видео» и в любом WebKit-видео на iOS 6.0 – 6.1.6.

Твик заменяет устаревшие системные кнопки перехода по главам на дискретную **перемотку на $\pm$10 секунд** с оригинальными круговыми стрелками в классическом стиле Apple. А неиспользуемая в полноэкранном режиме кнопка закладки превращается в **горизонтальный всплывающий HUD выбора скорости** (`0.5x` – `2.0x`).

---

## Основные возможности

- **Кнопки перемотки $\pm$10 с**
  - Заменяют кнопки предыдущего/следующего трека на скевоморфные круглые стрелки с цифрой `10`, выровненной строго по геометрии Apple.
  - Чистая Retina `@2x` графика без артефактов и наездов текста на контур.
  - Блокировка залипания непрерывного сканирования при долгом удержании.

- **Горизонтальный Segmented HUD (`0.5x`, `0.75x`, `1.0x`, `1.25x`, `1.5x`, `2.0x`)**
  - **Никаких вертикальных простыней и скролла**: все 6 скоростей умещаются в один ряд прямо над панелью управления в нативном стиле `UISegmentedControl` (`UIBarStyleBlackTranslucent`).
  - Выбор любой скорости (в том числе `2.0x`) ровно **в 1 клик**.
  - Плавное появление и автоскрытие через 0.3 с после выбора или 4 с бездействия.
  - Динамический бейдж на кнопке в плеере наглядно показывает текущую скорость (`0.5x`, `1x`, `2x` и т.д.).

- **Сохранение скорости при перемотке и паузе**
  - Хук `-[AVPlayer setRate:]` не дает системе сбрасывать выбранную скорость в 1.0x при перемещении ползунка видео или снятии с паузы.
  - Смена скорости на паузе оставляет видео на паузе до явного нажатия воспроизведения.
  - При начале воспроизведения нового видео скорость автоматически возвращается в стандартные `1.0x`.

- **Идеальное отображение в портретной ориентации**
  - Кнопка скорости отображается только в ландшафтном режиме, исключая переполнение и сжатие кнопок на узком экране в портрете.

---

## Совместимость

- **Версии iOS:** iOS 6.0, 6.1, 6.1.2, 6.1.3, 6.1.6.
- **Архитектура:** 32-bit ARMv7 (iPhone 3GS, iPhone 4, iPhone 4S, iPhone 5, iPod touch 3G/4G/5G, iPad 1/2/3/4/mini 1).
- **Substrate:** MobileSubstrate / Cydia Substrate / ElleKit.

---

## Использование ИИ (AI Disclosure)

Проект разработан с использованием языковых моделей (LLM / AI) для ускорения написания бойлерплейта, отладки и реверс-инжиниринга. Код вручную протестирован и доработан на реальном оборудовании (iPhone 4 и iPad mini 1 на iOS 6.1.2).

---

## Установка

### Через Cydia (Рекомендуется)
1. Откройте **Cydia** на вашем устройстве с джейлбрейком.
2. Перейдите в **Управление** → **Источники** → **Правка** → **Добавить**.
3. Введите адрес: `https://noname122021.github.io/cydia-repo/`
4. Найдите **VideoControls+** и нажмите **Установить**.

### Ручная установка .deb
Скачайте `com.noname122021.videocontrolsplus_1.0.2_iphoneos-arm.deb` из вкладки [Releases](https://github.com/noname122021/videocontrolsplus/releases) и установите через iFile или терминал:
```bash
dpkg -i com.noname122021.videocontrolsplus_1.0.2_iphoneos-arm.deb
killall -9 YouTube MobileSafari Videos
```

---

## Сборка из исходников

### Требования
- Установленный тулчейн [Theos](https://theos.dev/).
- iOS SDK 6.1+ (с поддержкой архитектуры ARMv7).

```bash
git clone https://github.com/noname122021/videocontrolsplus.git
cd videocontrolsplus/tweak
make clean package FINALPACKAGE=1
```

---

## Лицензия
MIT License. Автор: noname122021.
