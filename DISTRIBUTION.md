# Варианты поставки

## 1) Полный комплект (для новичков)

Файлы:

- `install-windows.bat`
- `install-windows.ps1`
- папки `extension/`, `controller/`
- `uninstall-windows.ps1`

Что делает:

- ставит локальный runtime (Node + Xray + controller)
- пытается автоматически установить Google Chrome, если не найден
- создает ярлыки и автозапуск контроллера
- открывает Chrome с локально загруженным расширением

## 2) Комплект для пользователей из маркетплейса

Файлы:

- `install-marketplace-windows.bat`
- `install-marketplace-windows.ps1`
- папка `controller/`
- `uninstall-windows.ps1`

Что делает:

- ставит только локальный runtime (Node + Xray + controller)
- пользователь ставит само расширение из Chrome Web Store

## Рекомендация

- Для прямых продаж/поддержки: используйте полный комплект.
- Для Chrome Web Store: публикуйте расширение + давайте ссылку на companion-установщик.
