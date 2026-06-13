
Directories and .zips in mods/ are not searched recursively. This way, you can have a simple disabled/ folder where you put all your unused mods

Names of mod directories and .zips are ignored. Name fields are used instead

The game will warn when trying to load mods with invalid dependencies or SemVer

init.lua is called at program start, use it wisely

tiles/, objects/, and levels/ are searched recursively so they can be organized in subfolders

Tiles, objects, and levels must have a .json file associated with them, otherwise their .lua files are ignored
Corresponding .lua files must have the same filename (minus extension) as the .json file

Tile ch field takes the first character or an empty space if an empty string

The global lua functions init, deinit, enter, exit, update, and generateTile are only allowed in level.lua files

The mods table may be used to access data of the current or other mods

No guarantees are made about the order of same-name function calls. init functions may happen in any order, as may update functions

Mod defined global variables are not allowed. Instead, fields may be added to the mods.modName table

All tile/object/level ids are sequential per mod

Key names in inputs.json are case-insensitive, but are PascalCase by convention
Key combinations must be in the format [modifiers] <final key>
