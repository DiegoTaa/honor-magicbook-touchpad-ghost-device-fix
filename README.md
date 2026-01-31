# honor-magicbook-touchpad-ghost-device-fix
Исправление самопроизвольной смены яркости экрана в Linux на ноутбуке Honor MagicBook. (Модель ноутбука: HONOR MagicBook X14 2025 5301ALWG/FRG-X)

# Блокировка фантомного устройства touchpad-контроллера GXTP7863

## Что происходит

Touchpad-контроллер `GXTP7863` создаёт несколько `input`-устройств. Среди них есть фантомное устройство с именем `UNKNOWN` и обработчиком `kbd`, которое постоянно спамит кейкодами даже без прикосновения к тачпаду. Эти коды могут попадать в управление яркостью, вызывая её произвольные скачки.

Настоящий тачпад и фантомное устройство имеют одинаковые `Vendor`, `Product` и `Version`, но различаются по значению `properties`:

| Устройство | Name | Handlers | PROP |
|---|---|---|---|
| Настоящий тачпад | `...Touchpad` | `mouse` | `5` |
| Фантомное | `...UNKNOWN` | `kbd` | `0` |

## Как убедиться что проблема та же

Запустить:

```bash
cat /proc/bus/input/devices
```

Искать два устройства с одинаковыми `Vendor` и `Product` от контроллера `GXTP7863`. Одно будет называться `Touchpad` с `PROP=5`, второе - `UNKNOWN` с `PROP=0` и `Handlers=kbd`. Второе и нужно блокировать.

## Решение

Создаём udev-правило, которое автоматически блокирует фантомное устройство при загрузке системы.

### 1. Создать файл правила

```bash
sudo nano /etc/udev/rules.d/99-block-gxtp7863-ghost.rules
```

Содержимое файла:

```
ACTION=="add", \
  ATTRS{id/bustype}=="0018", \
  ATTRS{id/vendor}=="27c6", \
  ATTRS{id/product}=="01e0", \
  ATTRS{id/version}=="0100", \
  ATTRS{properties}=="0", \
  ATTR{inhibited}="1"
```

> **Примечание:** значения `vendor`, `product`, `version` и `bustype` могут отличаться на другом ноутбуке - берите их из вывода `cat /proc/bus/input/devices` для фантомного устройства. Ключевой различающий признак - `ATTRS{properties}=="0"`.

### 2. Проверить синтаксис правила

Взять путь `Sysfs=` фантомного устройства из вывода `cat /proc/bus/input/devices` и подставить:

```bash
sudo udevadm test /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input13 2>&1 | grep -E "inhibit|Running|ATTR"
```

В выводе должна появиться строка с `ATTR{inhibited}` и `set to '1'` (или `skipping writing` в тестовом режиме). Если такой строки нет - проверяете значения в правиле.

### 3. Применить правило

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input13
```

> **Примечание:** путь после `--action=add` должен начинаться с `/sys/` и соответствовать пути `Sysfs=` фантомного устройства.

### 4. Проверить результат

Фантомное устройство должно быть заблокировано:

```bash
cat /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input13/inhibited
# Ожидаемый вывод: 1
```

Настоящий тачпад должен остаться рабочим:

```bash
cat /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input12/inhibited
# Ожидаемый вывод: 0
```

### 5. Перезагрузить ноут

После перезагрузки правило применится автоматически. Проблема с яркостью должна исчезнуть.

## Если что-то пошло не так

- Если `inhibited` не появляется - проверить путь к файлу: `find /sys/devices/pci0000:00/0000:00:15.0/ -name "inhibited"`. Файл может быть на другом уровне иерархии, тогда в правиле вместо `ATTR{inhibited}` может потребоваться `ATTR{../inhibited}`.
- Если `udevadm trigger` без явного пути не применяет правило - указать полный путь с `/sys/` и добавить `--action=add`.
- Если номера `input11`, `input12`, `input13` отличаются - ориентироваться по `Name` и `PROP` из вывода `cat /proc/bus/input/devices`, а не по номерам.
