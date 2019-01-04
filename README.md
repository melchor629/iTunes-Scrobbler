# iTunes Scrobbler
An alternative scrobbler for iTunes on macOS 10.12 or higher

## Features

 - Scrobbles from iTunes
 - It's CPU efficient
 - Uses little memory
 - Has a database to store every scrobble before sent to Last.fm
 - Can be opened at login, instead when iTunes open
 - Can see and manipulate the scrobbles in cache
 - You can disable send the scrobbles and store them all in the cache
 - It's open source :)

**Download now** in [zip][1] or [7z][2].

## Why an alternative scrobbler?
If you try to use the official Last.fm Scrobbler in 10.12 or higher, you get all the time an _"Device Scrobbles"_ notification. It's easy to avoid. Also, sometimes, the scrobbler doesn't open or gets stuck while opening and it's kind frustrating. But, the worst of all above is that cannot cache the scrobbles.

## Found an error or a crash?
Look for the logs at `/Users/<YOUR_USER>/Library/Logs/iTunesScrobbler/`, grab the latest file (the pattern of them are always `iTunes Scrobbler.yyyy.MM.dd.log`). Then fill an issue [here][3].

## API Keys
If you try to use the app building from it's sources, you first need to set up your last.fm developer keys and github token. To achieve that, modify the file `iTunes Scrobbler/Tokens.swift` and put there your API Keys.


  [1]: https://github.com/melchor629/iTunes-Scrobbler/releases/download/v0.2.3/iTunes.Scrobbler.zip
  [2]: https://github.com/melchor629/iTunes-Scrobbler/releases/download/v0.2.3/iTunes.Scrobbler.7z
  [3]: https://github.com/melchor629/iTunes-Scrobbler/issues/new
