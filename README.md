# WowBox

WoW Forever addon. Lists the Waylaid Crates and Craftsman's Writs in your bags. Click one and Auctionator searches those items in its shopping tab, so you can see which crate fill is cheapest, or buy the item a writ asks for.

A crate search includes every bundle on the crate, for example Dream Dust, Greater Nether Essence, Small Brilliant Shard and Large Brilliant Shard. A writ search uses the item in the name. Craftsman's Writ: Sniper Scope searches for Sniper Scope.

Needs Auctionator.

## Install

Quit the game, then put this folder here (the folder name and the `.toc` name must match):

```
World of Warcraft\_forever_\Interface\AddOns\wowbox\
```

The Battle.net / Steam install is usually:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\wowbox\
```

That folder must contain `wowbox.toc` and `wowbox.lua` directly, not one directory deeper.

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
