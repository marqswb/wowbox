# WowBox

WoW Forever addon. Lists every Waylaid Crate and every Craftsman's Writ, not only the ones in your bags. A count sits on each row: how many you are carrying, or x0 if you have none. What you have is listed first.

Click a row and Auctionator searches that crate or writ itself, plus everything that fills it. A crate search is the crate and every bundle, so you can compare buying the crate with buying Dream Dust, Greater Nether Essence, and the rest. A writ search is the writ and the item it asks for. Craftsman's Writ: Sniper Scope searches for the writ and for Sniper Scope.

Needs Auctionator. The window background is solid, like the auction house.

## Install

Quit the game, then put this folder here (the folder name and the `.toc` name must match):

```
World of Warcraft\_forever_\Interface\AddOns\wowbox\
```

The Battle.net / Steam install is usually:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\wowbox\
```

That folder must contain `wowbox.toc`, `wowbox_data.lua` and `wowbox.lua` directly, not one directory deeper.

From the `AddOns` folder:

```
git clone https://github.com/marqswb/wowbox.git
```

If you already cloned it, `git pull` inside the `wowbox` folder.

Start the game fully after the first copy. `/reload` is not enough the first time an addon is added. In the character list, AddOns, enable **WowBox** and **Auctionator**.

## Try it

1. Have a Waylaid Crate or a Craftsman's Writ in your bags.
2. Open the auction house. WowBox opens on its own.
3. Click a crate. Auctionator's shopping tab searches every item that can fill it.
4. Click a writ. It searches the item named after the colon.

`/wowbox` (or `/wb`) opens the list when you are not at the auction house. The search itself still needs the auction house to be open.

## Commands

| Command | What it does |
| --- | --- |
| `/wowbox` | Show or hide the list |
| `/wb` | Same |
| `/wowbox auto` | Stop or start opening the list when the auction house opens |
| `/wowbox debug` | Print the tooltip lines and what was parsed for the first crate or writ |

If a crate row says it could not read the list, hover that crate and run `/wowbox debug`.
