# Публикация проекта на GitHub (пошагово)

## Что важно указать в описании

VLESS-ссылка выдается только по запросу в поддержку:

1. Войти в личный кабинет: https://cp.sevenskull.ru/login
2. Создать тикет в поддержку
3. Запросить VLESS-конфигурацию (`vless://...`)

Без этой ссылки подключение VPN невозможно.

## 1) Создайте новый репозиторий на GitHub

1. Откройте https://github.com/new
2. Repository name: например `vless-vpn-chrome`
3. Visibility: `Public` или `Private`
4. Нажмите **Create repository**

## 2) Загрузите проект из папки на компьютере

Откройте терминал в папке проекта и выполните:

```bash
git init
git add .
git commit -m "Initial release: VLESS VPN Chrome extension + Windows installer"
git branch -M main
git remote add origin https://github.com/USERNAME/REPO.git
git push -u origin main
```

Замените `USERNAME/REPO` на ваш GitHub-репозиторий.

## 3) Что добавить в описание репозитория

Рекомендуемый текст:

`VLESS VPN for Google Chrome (Windows 7/10/11). Paste vless:// link and enable VPN in browser.`

## 4) Что добавить в README

Обязательно оставьте пункт:

- VLESS-ссылка выдается через тикет в поддержке в личном кабинете: https://cp.sevenskull.ru/login

## 5) Что прикрепить в Releases (по желанию)

Можно загрузить готовый архив для пользователей:

- полный комплект (installer + extension + controller)
- marketplace-companion комплект

## 6) Частые проблемы при push

- `Authentication failed` — войдите в GitHub Desktop или настройте Personal Access Token.
- `remote origin already exists` — удалите старый remote: `git remote remove origin` и добавьте заново.
- `src refspec main does not match any` — сначала сделайте commit.
